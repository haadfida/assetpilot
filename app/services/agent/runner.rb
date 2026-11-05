module Agent
  # The live agent loop (the "AgentRun service"; AgentRun itself is the ActiveRecord model for agent_runs).
  #
  # A manual tool-use loop over client.beta.messages.stream: stream a turn, forward text/progress deltas,
  # and if the model stopped for tool_use run every requested tool and send all results back in one user
  # message. Stops on end_turn, refusal, max_tokens, an API error, or after `max_tool_iterations` tool turns.
  #
  # The conversation is append-only: assistant turns go back exactly as received, thinking blocks and their
  # signatures included, so preserved thinking and the prompt cache stay valid.
  class Runner
    attr_reader :run, :recorder, :config

    def initialize(run:, client:, recorder:, config: Config.current)
      @run = run
      @client = client
      @recorder = recorder
      @config = config
      @usage = Hash.new(0)
      @iterations = 0
      @api_key = nil
    end

    # api_key is only used to scrub it from error messages before they are stored.
    def call(api_key: nil)
      @api_key = api_key
      messages = [Agent.first_user_message(run.prompt)]

      loop do
        if @iterations >= config.max_tool_iterations
          return fail!("max_iterations", "iteration_cap",
                       "Stopped after #{config.max_tool_iterations} tool iterations without a final answer")
        end

        message = stream_turn(messages)
        add_usage(message.usage)

        case message.stop_reason
        when :refusal
          category = message.try(:stop_details)&.category
          return fail!("refused", "refusal", "The model declined this request#{" (#{category})" if category}.",
                       stop_reason: "refusal")
        when :max_tokens
          # A tool_use cut off here may parse as a valid partial object: never run it.
          return fail!("failed", "max_tokens", "The response hit max_tokens before finishing.", stop_reason: "max_tokens")
        when :tool_use
          @iterations += 1
          recorder.iteration = @iterations
          messages << { role: "assistant", content: message.content.map { |b| assistant_block(b) } }
          results = message.content.select { |b| b.type == :tool_use }.map { |b| run_tool(b) }
          messages << { role: "user", content: results }
        else
          return finish!("succeeded", stop_reason: message.stop_reason.to_s)
        end
      end
    rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError => e
      fail!("failed", "invalid_api_key", "The Anthropic API rejected the key (HTTP #{e.status}).")
    rescue Anthropic::Errors::RateLimitError
      fail!("failed", "upstream_rate_limited", "The Anthropic API rate-limited this key; try again shortly.")
    rescue Anthropic::Errors::APIStatusError => e
      fail!("failed", "api_error", "Anthropic API error (HTTP #{e.status}): #{scrub(e.message).first(300)}")
    rescue Anthropic::Errors::APIConnectionError => e
      fail!("failed", "connection_error", "Could not reach the Anthropic API: #{e.class.name.demodulize}")
    rescue StandardError => e
      Rails.logger.error("[agent] run #{run.id} crashed: #{e.class}: #{scrub(e.message)}")
      fail!("failed", "internal_error", "The agent stopped because of an internal error.")
    end

    private

    def stream_turn(messages)
      stream = @client.beta.messages.stream(**config.request(messages))
      stream.each do |event|
        case event.type
        when :text then recorder.text_delta(event.text)
        when :thinking then recorder.progress_delta(event.thinking) # display "updates": non-empty = progress note
        when :content_block_stop then recorder.close_block
        end
      end
      stream.accumulated_message
    ensure
      stream&.close if stream.respond_to?(:close)
    end

    def run_tool(block)
      input = block.input
      recorder.tool_call(id: block.id, name: block.name, input: input.is_a?(Hash) ? input : { "_raw" => input.to_s })
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # eager_input_streaming: the SDK leaves unparseable input as the raw String. Don't run the tool;
      # send the raw text back as an error so the model can retry (skill pattern: INVALID_JSON).
      result, content =
        if input.is_a?(Hash)
          r = Tools::Registry.call(block.name, input)
          [r, JSON.generate(r)]
        else
          [{ "ok" => false, "error" => { "code" => "INVALID_JSON", "message" => "Tool input was not valid JSON",
                                         "details" => { "raw" => input.to_s.first(2000) } } },
           JSON.generate("INVALID_JSON" => input.to_s)]
        end

      is_error = !result["ok"]
      recorder.tool_result(tool_use_id: block.id, name: block.name, output: result, is_error: is_error,
                           duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      { type: "tool_result", tool_use_id: block.id, content: content, is_error: is_error }
    end

    # Assistant blocks are sent back unchanged (thinking signatures included).
    def assistant_block(block)
      case block.type
      when :text then { type: "text", text: block.text }
      when :thinking then { type: "thinking", thinking: block.thinking, signature: block.signature }
      when :redacted_thinking then { type: "redacted_thinking", data: block.data }
      when :tool_use
        input = block.input.is_a?(Hash) ? block.input : (JSON.parse(block.input.to_s) rescue {})
        { type: "tool_use", id: block.id, name: block.name, input: input }
      else block.to_h.except(:parsed)
      end
    end

    def add_usage(usage)
      return unless usage

      %i[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].each do |k|
        @usage[k] += usage.public_send(k).to_i if usage.respond_to?(k)
      end
    end

    def finish!(status, stop_reason:)
      recorder.finish!(status: status, stop_reason: stop_reason, usage: @usage, iterations: @iterations)
    end

    def fail!(status, code, message, stop_reason: nil)
      message = scrub(message)
      recorder.error(code: code, message: message)
      recorder.finish!(status: status, stop_reason: stop_reason, usage: @usage, iterations: @iterations,
                       error_code: code, error_message: message)
    end

    def scrub(text)
      text = text.to_s
      @api_key.present? ? text.gsub(@api_key, "[FILTERED]") : text
    end
  end
end

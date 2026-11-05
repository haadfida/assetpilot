module Replays
  # Records one synthetic run while its tools execute for real. A scenario script drives it:
  #
  #   s.turn("Checking the dependency graph.") { |t| t.call("impact_analysis", node_type: "asset", node: "DB-Server") }
  #   s.answer("If DB-Server goes down ...")
  #
  # Every `call` runs the real tool against the database and records its actual output. Timings are
  # synthetic but plausible: a fixed model latency per turn, a streaming rate for text, and the measured
  # duration of each tool call. Token usage is estimated from text length (marked "estimated").
  class Session
    TURN_LATENCY_MS = 1_200       # time to first token for a model turn
    TOOL_INPUT_MS = 350           # emitting a tool_use block
    MS_PER_CHAR = 12              # ~80 characters per second of streamed text
    PREFIX_TOKENS_PER_CHAR = 0.25 # rough chars -> tokens

    attr_reader :steps, :iterations

    def initialize(prompt)
      @prompt = prompt
      @steps = []
      @t = 0
      @iterations = 0
      @tool_seq = 0
      @input_tokens = 0
      @output_chars = 0
      @context_chars = prefix_chars + prompt.size
    end

    # One model turn that ends in tool use. Yields a Turn; returns the block's value.
    def turn(progress = nil)
      @iterations += 1
      model_turn_start
      if progress
        text_step("progress", progress)
        @context_chars += progress.size
      end
      turn = Turn.new(self)
      value = yield turn
      value
    end

    # The final model turn: streamed text, end_turn.
    def answer(text)
      model_turn_start
      text_step("text", text)
    end

    def record_call(name, input)
      @tool_seq += 1
      id = format("toolu_replay_%02d", @tool_seq)
      input = input.deep_stringify_keys
      @t += TOOL_INPUT_MS
      @steps << { "t_ms" => @t, "type" => "tool_use", "iteration" => @iterations, "id" => id, "name" => name, "input" => input }
      @output_chars += input.to_json.size

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output = Tools::Registry.call(name, input)
      duration = [((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round, 1].max
      @t += duration
      @steps << { "t_ms" => @t, "type" => "tool_result", "iteration" => @iterations, "tool_use_id" => id, "name" => name,
                  "is_error" => !output["ok"], "duration_ms" => duration, "output" => output }
      @context_chars += input.to_json.size + output.to_json.size
      output
    end

    def duration_ms = @t

    def usage
      { "input_tokens" => @input_tokens, "output_tokens" => (@output_chars * PREFIX_TOKENS_PER_CHAR).ceil,
        "cache_read_input_tokens" => 0, "cache_creation_input_tokens" => 0, "estimated" => true }
    end

    private

    def model_turn_start
      @t += TURN_LATENCY_MS
      @input_tokens += (@context_chars * PREFIX_TOKENS_PER_CHAR).ceil
    end

    def text_step(type, text)
      duration = text.size * MS_PER_CHAR
      @steps << { "t_ms" => @t, "type" => type, "iteration" => @iterations, "text" => text, "duration_ms" => duration }
      @t += duration
      @output_chars += text.size
    end

    def prefix_chars
      (Agent::SYSTEM_PROMPT.size + Tools::Registry.definitions.to_json.size)
    end

    class Turn
      def initialize(session) = @session = session

      # Runs the tool for real; returns its `data` (or the whole error result when it failed).
      def call(name, input = {})
        result = @session.record_call(name, input)
        result["ok"] ? result["data"] : result
      end
    end
  end
end

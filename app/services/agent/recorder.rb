module Agent
  # Persists a run's steps in order and emits the matching stream events. Live runs and replays both go
  # through this class, so the SSE pipeline cannot tell them apart (except for the run's mode/recorded flags).
  #
  # Events: text / progress {step, delta}, tool_call {step, id, name, input},
  # tool_result {step, tool_use_id, name, is_error, output, duration_ms}, error {step, code, message}, done {...}.
  # Text and progress deltas are emitted as they arrive and stored as one row per content block.
  class Recorder
    attr_reader :run
    attr_accessor :iteration

    def initialize(run, emit: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @run = run
      @emit = emit || ->(_event, _data) {}
      @clock = clock
      @t0 = clock.call
      @position = (run.steps.maximum(:position) || -1) + 1
      @open = nil
      @iteration = 0
      @listening = true
    end

    def listening? = @listening

    def elapsed_ms = ((@clock.call - @t0) * 1000).round

    def text_delta(str) = delta("text", str)
    def progress_delta(str) = delta("progress", str)

    def close_block
      return unless (block = @open)

      @open = nil
      persist(position: block[:position], kind: block[:kind], content: block[:buffer],
              elapsed_ms: block[:started_ms], duration_ms: elapsed_ms - block[:started_ms])
    end

    def tool_call(id:, name:, input:)
      close_block
      step = persist(kind: "tool_use", tool_use_id: id, tool_name: name, input: input, elapsed_ms: elapsed_ms)
      emit(:tool_call, step.as_event)
    end

    def tool_result(tool_use_id:, name:, output:, is_error:, duration_ms:)
      close_block
      step = persist(kind: "tool_result", tool_use_id: tool_use_id, tool_name: name, output: output,
                     is_error: is_error, elapsed_ms: elapsed_ms, duration_ms: duration_ms)
      emit(:tool_result, step.as_event)
    end

    def error(code:, message:)
      close_block
      step = persist(kind: "error", content: message, output: { code: code }, is_error: true, elapsed_ms: elapsed_ms)
      emit(:error, step.as_event)
    end

    def finish!(status:, stop_reason: nil, usage: {}, iterations: iteration, error_code: nil, error_message: nil)
      close_block
      run.update!(status: status, stop_reason: stop_reason, iterations: iterations, error_code: error_code,
                  error_message: error_message, finished_at: Time.current, duration_ms: elapsed_ms,
                  **usage.slice(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens))
      emit(:done, done_payload)
    end

    def done_payload
      run.summary.slice(:id, :status, :mode, :recorded, :model, :iterations, :stop_reason, :usage, :duration_ms, :error)
         .merge(steps: run.steps.count)
    end

    # Re-emits a finished run's stored steps (no timing) and its done event.
    def emit_stored
      run.steps.each do |step|
        event = { "text" => :text, "progress" => :progress, "tool_use" => :tool_call,
                  "tool_result" => :tool_result, "error" => :error }.fetch(step.kind)
        emit(event, step.as_event)
      end
      emit(:done, done_payload)
    end

    private

    def delta(kind, str)
      return if str.nil? || str.empty?

      close_block if @open && @open[:kind] != kind
      @open ||= { kind: kind, buffer: +"", started_ms: elapsed_ms, position: next_position! }
      @open[:buffer] << str
      emit(kind.to_sym, step: @open[:position], delta: str)
    end

    def persist(position: next_position!, **attrs)
      run.steps.create!(position: position, iteration: iteration, **attrs)
    end

    def next_position!
      @position.tap { @position += 1 }
    end

    # A disconnected client must not abort the run: keep executing and persisting, stop writing.
    def emit(event, data)
      return unless @listening

      @emit.call(event, data)
    rescue IOError, Errno::EPIPE, ActionController::Live::ClientDisconnected
      @listening = false
    end
  end
end

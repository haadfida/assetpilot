module Agent
  # Replays a recorded run through the same Recorder (and so the same SSE events and persisted steps) as a
  # live run, sleeping for the recorded gaps divided by `speed`. Tool results come from the recording:
  # replaying "check in AP-00021" does not touch the inventory.
  class Replayer
    MIN_SPEED = 0.1
    MAX_SPEED = 100.0
    CHUNK_WORDS = 3

    def initialize(run:, replay:, recorder:, speed: 1.0, sleeper: ->(seconds) { sleep(seconds) })
      @run = run
      @replay = replay
      @recorder = recorder
      @speed = speed.to_f.clamp(MIN_SPEED, MAX_SPEED)
      @sleeper = sleeper
    end

    def call
      cursor = 0
      @replay.steps.each do |step|
        wait(step["t_ms"] - cursor)
        cursor = step["t_ms"]
        @recorder.iteration = step.fetch("iteration", @recorder.iteration)

        case step["type"]
        when "text", "progress"
          chunks = step["text"].scan(/\S+\s*|\s+/).each_slice(CHUNK_WORDS).map(&:join)
          gap = step.fetch("duration_ms", 0).to_f / [chunks.size, 1].max
          chunks.each do |chunk|
            step["type"] == "text" ? @recorder.text_delta(chunk) : @recorder.progress_delta(chunk)
            wait(gap)
          end
          @recorder.close_block
          cursor += step.fetch("duration_ms", 0)
        when "tool_use"
          @recorder.tool_call(id: step["id"], name: step["name"], input: step["input"])
        when "tool_result"
          @recorder.tool_result(tool_use_id: step["tool_use_id"], name: step["name"], output: step["output"],
                                is_error: step["is_error"], duration_ms: step["duration_ms"])
        when "error"
          @recorder.error(code: step["code"], message: step["message"])
        end
      end

      @recorder.finish!(status: @replay.status, stop_reason: @replay.stop_reason, usage: @replay.usage,
                        iterations: @replay.iterations)
    end

    private

    # Once the client has gone, finish (and persist) without the delays.
    def wait(ms)
      return unless ms.to_f.positive? && @recorder.listening?

      @sleeper.call(ms.to_f / 1000 / @speed)
    end
  end
end

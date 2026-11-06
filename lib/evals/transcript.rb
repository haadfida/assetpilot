module Evals
  # What the grader sees of a run: its status, every tool call with its input and result, and the final
  # answer text. Built from a live AgentRun, from a db/replays fixture, or by executing a list of calls
  # against the database (oracles and spec fixtures).
  class Transcript
    Call = Struct.new(:name, :input, :output, keyword_init: true) do
      def ok? = output.is_a?(Hash) && output["ok"] == true
      def error_code = ok? ? nil : output&.dig("error", "code")
      def as_json(*) = { "name" => name, "input" => input, "ok" => ok?, "error_code" => error_code }
    end

    attr_reader :status, :calls, :final_text, :meta

    def initialize(status:, calls:, final_text:, meta: {})
      @status = status
      @calls = calls
      @final_text = final_text.to_s
      @meta = meta
    end

    def self.from_run(run)
      steps = run.steps.to_a
      results = steps.select { |s| s.kind == "tool_result" }.index_by(&:tool_use_id)
      calls = steps.select { |s| s.kind == "tool_use" }.map do |s|
        Call.new(name: s.tool_name, input: s.input || {}, output: results[s.tool_use_id]&.output)
      end
      new(status: run.status, calls: calls, final_text: final_text(steps.map { |s| [s.kind, s.content] }),
          meta: { "run_id" => run.id, "iterations" => run.iterations, "stop_reason" => run.stop_reason,
                  "error" => run.error_code, "usage" => run.usage.transform_values(&:to_i) })
    end

    # A db/replays fixture. Tool outputs are re-executed (they are verified identical by replays:verify) so the
    # database ends up in the state the recorded run left it in.
    def self.from_replay(fixture)
      calls = fixture["steps"].select { |s| s["type"] == "tool_use" }.map do |s|
        Call.new(name: s["name"], input: s["input"], output: Tools::Registry.call(s["name"], s["input"]))
      end
      new(status: fixture["status"], calls: calls,
          final_text: final_text(fixture["steps"].map { |s| [s["type"], s["text"]] }), meta: { "replay" => fixture["slug"] })
    end

    # Executes each {name, input} against the real tools, in order. A call that carries an "output" is not
    # executed; that output is used as given (spec fixtures that simulate a tool misbehaving).
    def self.execute(calls, answer: "", status: "succeeded")
      executed = Array(calls).map do |c|
        input = c["input"] || {}
        Call.new(name: c["name"], input: input, output: c.key?("output") ? c["output"] : Tools::Registry.call(c["name"], input))
      end
      new(status: status, calls: executed, final_text: answer)
    end

    def self.null = new(status: "succeeded", calls: [], final_text: "")

    # The answer is the text after the last tool result (all text if there was no tool call).
    def self.final_text(kinds_and_text)
      last_result = kinds_and_text.rindex { |k, _| %w[tool_result tool_use].include?(k) }
      tail = last_result ? kinds_and_text[(last_result + 1)..] : kinds_and_text
      tail.select { |k, _| k == "text" }.map(&:last).join
    end

    def as_json(*) = { "status" => status, "calls" => calls.map(&:as_json), "final_text" => final_text, "meta" => meta }
  end
end

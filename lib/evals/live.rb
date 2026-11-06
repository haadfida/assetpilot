module Evals
  # Live mode: each case runs the real Agent::Runner against the Claude API, inside the eval sandbox (its own
  # savepoint of a rolled-back, reseeded, clock-frozen transaction), so mutating tools change the seeded
  # database for that case only. Grading is deterministic (Evals::Grader); --judge adds Evals::Judge.
  class Live
    CaseResult = Struct.new(:kase, :status, :grade, :transcript, :db, :judge, :duration_ms, :error, keyword_init: true) do
      # "graded" when the run produced a transcript, "error" when the API call itself failed (not a grade 0).
      def pass = status == "graded" && grade.pass

      def as_json(*)
        { "id" => kase.id, "tags" => kase.tags, "prompt" => kase.prompt, "status" => status, "pass" => pass,
          "dimensions" => grade&.dimensions, "failures" => grade&.failures, "db" => db&.map(&:as_json),
          "transcript" => transcript&.as_json, "judge" => judge, "duration_ms" => duration_ms, "error" => error }
      end
    end

    # Run errors that mean the API call failed, as opposed to the agent behaving badly.
    INFRA_ERRORS = %w[invalid_api_key upstream_rate_limited api_error connection_error].freeze

    def initialize(cases, api_key:, config: Agent::Config.current, judge: nil, client: nil, log: $stderr)
      @cases = cases
      @api_key = api_key
      @config = config
      @judge = judge
      @client = client || Agent.build_client(api_key)
      @log = log
    end

    def run
      Sandbox.run do
        @cases.each_with_index.map do |kase, i|
          result = Sandbox.isolated { run_case(kase) }
          @log&.puts(format("[%2d/%d] %-4s %-34s %s", i + 1, @cases.size, result.pass ? "PASS" : (result.status == "error" ? "ERR" : "FAIL"),
                            kase.id, result.grade&.failures&.first || result.error))
          raise Abort, result.error if result.error.to_s.start_with?("invalid_api_key")

          result
        end
      end
    end

    class Abort < StandardError; end

    private

    def run_case(kase)
      before = DbState.snapshot
      run = AgentRun.create!(prompt: kase.prompt, model: @config.model, mode: "live", status: "running", started_at: Time.current)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Agent::Runner.new(run: run, client: @client, recorder: Agent::Recorder.new(run), config: @config).call(api_key: @api_key)
      run.reload
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      if INFRA_ERRORS.include?(run.error_code)
        return CaseResult.new(kase: kase, status: "error", duration_ms: ms, error: "#{run.error_code}: #{run.error_message}")
      end

      transcript = Transcript.from_run(run)
      db = before.evaluate(kase.db_assertions)
      grade = Grader.grade(kase, transcript, db)
      judged = @judge&.call(kase, transcript)
      CaseResult.new(kase: kase, status: "graded", grade: grade, transcript: transcript, db: db, judge: judged, duration_ms: ms)
    end
  end
end

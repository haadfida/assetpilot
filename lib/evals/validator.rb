module Evals
  # Offline mode. Needs no API key and makes no network call. For every case it checks:
  #
  #   structure   known keys and tags, unique ids, a prompt, an oracle
  #   schemas     tool names exist; argument names exist in the tool's input schema; literal matcher values
  #               satisfy the argument's schema (enums, formats); regexes compile; error codes are real;
  #               db assertions are well-formed; mutating cases assert database state
  #   seed refs   every asset, person, service and location the case names resolves as declared
  #   oracle      the reference trajectory runs through the real tools against the seed and passes the grader
  #               (so the expected tools, arguments, outcomes and db state are reachable)
  #   null        an empty transcript (no calls, no text) fails the case, so the case can tell a no-op apart
  #   replay      when linked, the recorded db/replays trajectory passes too
  class Validator
    ID_FORMAT = /\A[a-z0-9][a-z0-9-]*\z/
    ERROR_CODES = %w[invalid_input not_found ambiguous already_checked_out asset_unavailable invalid_due_date
                     not_checked_out validation_failed internal_error unknown_tool].freeze

    CaseReport = Struct.new(:kase, :problems, :oracle, :null, :replay, keyword_init: true) do
      def pass = problems.empty?

      def as_json(*)
        { "id" => kase.id, "tags" => kase.tags, "pass" => pass, "problems" => problems,
          "oracle" => oracle&.as_json, "null_transcript_fails" => null && !null.pass, "replay" => replay&.as_json }
      end
    end

    def initialize(cases)
      @cases = cases
    end

    def run
      dupes = @cases.map(&:id).tally.select { |_, n| n > 1 }.keys
      Sandbox.run do
        @cases.map do |kase|
          problems = static_problems(kase)
          problems << "duplicate id #{kase.id}" if dupes.include?(kase.id)
          next CaseReport.new(kase: kase, problems: problems) if problems.any?

          problems += ref_problems(kase)
          oracle = Sandbox.isolated { grade_with(kase) { Transcript.execute(kase.oracle["calls"], answer: kase.oracle["answer"].to_s) } }
          problems += oracle.failures.map { |f| "oracle fails: #{f}" } unless oracle.pass
          null = Sandbox.isolated { grade_with(kase) { Transcript.null } }
          problems << "an empty transcript passes this case; it cannot detect a no-op" if null.pass
          replay = nil
          if kase.replay
            fixture = JSON.parse(Agent::Replays::DIR.join("#{kase.replay}.json").read)
            replay = Sandbox.isolated { grade_with(kase) { Transcript.from_replay(fixture) } }
            problems += replay.failures.map { |f| "replay #{kase.replay} fails: #{f}" } unless replay.pass
          end
          CaseReport.new(kase: kase, problems: problems, oracle: oracle, null: null, replay: replay)
        end
      end
    end

    private

    def grade_with(kase)
      before = DbState.snapshot
      transcript = yield
      Grader.grade(kase, transcript, before.evaluate(kase.db_assertions))
    end

    def static_problems(kase)
      p = []
      raw = kase.raw
      p << "unknown keys: #{(raw.keys - Case::KEYS).join(', ')}" if (raw.keys - Case::KEYS).any?
      p << "id must match #{ID_FORMAT.source}" unless kase.id.is_a?(String) && kase.id.match?(ID_FORMAT)
      p << "prompt is empty" unless kase.prompt.is_a?(String) && kase.prompt.strip.present?
      p << "tags are empty" if kase.tags.empty?
      p << "unknown tags: #{(kase.tags - TAGS).join(', ')}" if (kase.tags - TAGS).any?

      et = kase.expected_tools
      p << "expected_tools is required" unless raw.key?("expected_tools")
      p << "expected_tools.order must be ordered or unordered" unless %w[ordered unordered].include?(kase.order)
      p << "unknown expected_tools keys: #{(et.keys - %w[order calls forbidden max_calls]).join(', ')}" if (et.keys - %w[order calls forbidden max_calls]).any?
      p << "max_calls must be a non-negative integer" if et.key?("max_calls") && !(et["max_calls"].is_a?(Integer) && et["max_calls"] >= 0)
      Array(et["forbidden"]).each { |n| p << "forbidden: unknown tool #{n}" unless Tools::Registry.fetch(n) }
      kase.call_specs.each_with_index do |spec, i|
        alts = spec["any_of"] || [spec]
        p << "calls[#{i}].any_of is empty" if alts.empty?
        alts.each { |s| p.concat(call_spec_problems(s, "calls[#{i}]")) }
      end

      eo = raw["expected_outcome"] || {}
      p << "expected_outcome.run must be one of #{AgentRun::FINISHED.join('/')}" unless AgentRun::FINISHED.include?(kase.expected_run_status)
      if (kase.mutating_expected? || kase.tags.include?("write")) && eo["db"].blank?
        p << "a case that expects a mutating tool (or is tagged write) needs expected_outcome.db assertions"
      end
      kase.db_assertions.each { |a| p.concat(DbState.problems(a).map { |x| "db: #{x}" }) }
      Array(eo["db"]).each do |a|
        tag_fields = %w[asset].select { |k| a.is_a?(Hash) && a[k].is_a?(String) && a["type"].in?(%w[asset_status open_checkout]) }
        tag_fields.each { |k| p << "db: #{a['type']}.#{k} #{a[k]} is not a seeded asset tag" unless Asset.exists?(tag: a[k]) }
      end

      kase.answer_patterns.each do |pat|
        Regexp.new(pat)
      rescue RegexpError, TypeError => e
        p << "answer pattern #{pat.inspect} does not compile: #{e.message}"
      end

      p.concat(oracle_problems(kase))
      Case::REF_KINDS.each { |k| kase.refs[k]&.each_value { |v| p << "refs.#{k}: unknown state #{v}" unless Case::REF_STATES.include?(v) } }
      p << "unknown ref kinds: #{(kase.refs.keys - Case::REF_KINDS).join(', ')}" if (kase.refs.keys - Case::REF_KINDS).any?
      p << "replay #{kase.replay} not found in db/replays" if kase.replay && !Agent::Replays::DIR.join("#{kase.replay}.json").exist?
      p
    end

    def call_spec_problems(spec, where)
      tool = Tools::Registry.fetch(spec["name"])
      return ["#{where}: unknown tool #{spec['name'].inspect}"] unless tool

      p = []
      p << "#{where}: unknown keys #{(spec.keys - %w[name args outcome]).join(', ')}" if (spec.keys - %w[name args outcome]).any?
      props = tool.input_schema.fetch("properties", {})
      (spec["args"] || {}).each do |arg, m|
        prop = props[arg]
        next p << "#{where}: #{tool.tool_name} has no argument #{arg}" unless prop

        matcher = Matcher.build(m)
        schema = matcher.kind.in?(%w[subset set]) ? prop["items"] : prop
        matcher.literal_values.each do |v|
          next unless schema

          errors = JSONSchemer.schema(schema, format: true).validate(v).map { |e| e["error"] }
          p << "#{where}: #{tool.tool_name}.#{arg} value #{v.to_json} violates its schema (#{errors.join('; ')})" if errors.any?
        end
      rescue Matcher::Invalid => e
        p << "#{where}: #{tool.tool_name}.#{arg}: #{e.message}"
      end
      outcome = spec.fetch("outcome", "ok")
      unless outcome.in?(%w[ok any]) || (outcome.is_a?(Hash) && outcome.keys == ["error"] && ERROR_CODES.include?(outcome["error"]))
        p << "#{where}: outcome must be ok, any or {\"error\": <#{ERROR_CODES.join('|')}>}"
      end
      p
    end

    def oracle_problems(kase)
      return ["oracle is required (calls and answer)"] unless kase.raw["oracle"].is_a?(Hash) && kase.oracle.key?("calls")

      Array(kase.oracle["calls"]).each_with_index.flat_map do |c, i|
        tool = Tools::Registry.fetch(c["name"])
        next ["oracle.calls[#{i}]: unknown tool #{c['name'].inspect}"] unless tool

        tool.schemer.validate(c["input"] || {}).map { |e| "oracle.calls[#{i}] input fails the #{tool.tool_name} schema: #{e['error']}" }
      end
    end

    def ref_problems(kase)
      resolver = RefResolver.new
      kase.refs.flat_map do |kind, refs|
        refs.filter_map do |ref, want|
          got = resolver.state(kind, ref)
          "refs.#{kind}: #{ref.inspect} is #{got} in the seed data, expected #{want}" unless got == want
        end
      end
    end
  end
end

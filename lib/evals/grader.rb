module Evals
  # Deterministic grader. Given a case, a transcript and the database-assertion results, it scores:
  #
  #   run      the run finished with the expected status (default "succeeded")
  #   tools    every required call's tool was called (in order when order is "ordered")
  #   args     ... with arguments that satisfy the matchers
  #   outcome  ... and each matched call ended as expected (ok / a given error code / any)
  #   hygiene  no forbidden tool, at most max_calls calls, no failed call repeated with the same input
  #   db       every database assertion holds
  #   answer   the final text contains every `answer.includes` pattern
  #
  # tools, args and outcome are nested: each matching step adds a condition to the one before, so the first
  # failing one says where the trajectory went wrong. A case passes when every dimension passes.
  class Grader
    DIMENSIONS = %w[run tools args outcome hygiene db answer].freeze

    Result = Struct.new(:case_id, :pass, :dimensions, :failures, keyword_init: true) do
      def as_json(*) = { "case_id" => case_id, "pass" => pass, "dimensions" => dimensions, "failures" => failures }
    end

    def self.grade(kase, transcript, db_results = []) = new(kase, transcript, db_results).grade

    def initialize(kase, transcript, db_results)
      @case = kase
      @t = transcript
      @db = db_results
      @failures = []
    end

    def grade
      dims = {}
      dims["run"] = check(@t.status == @case.expected_run_status, "run status #{@t.status}, expected #{@case.expected_run_status}")

      tools = assign(->(spec, call) { spec["name"] == call.name })
      args = tools && assign(->(spec, call) { spec["name"] == call.name && args_match?(spec, call) })
      outcome = args && assign(->(spec, call) { spec["name"] == call.name && args_match?(spec, call) && outcome_match?(spec, call) })
      dims["tools"] = check(!tools.nil?, "required tools not called#{' in order' if ordered?}: #{required_desc}; called #{called_desc}")
      dims["args"] = tools ? check(!args.nil?, "no call with matching arguments: #{arg_mismatch_desc}") : false
      dims["outcome"] = args ? check(!outcome.nil?, "matched calls ended differently than expected: #{outcome_desc}") : false

      dims["hygiene"] = hygiene
      bad_db = @db.reject(&:pass)
      dims["db"] = check(bad_db.empty?, "db: #{bad_db.map { |r| "#{r.assertion['type']} (#{r.detail})" }.join('; ')}")
      missing = @case.answer_patterns.reject { |p| Regexp.new(p, Regexp::IGNORECASE).match?(@t.final_text) }
      dims["answer"] = check(missing.empty?, "answer lacks #{missing.map { |p| "/#{p}/" }.join(', ')}")

      Result.new(case_id: @case.id, pass: dims.values.all?, dimensions: dims, failures: @failures)
    end

    private

    def ordered? = @case.order == "ordered"

    def check(ok, message)
      @failures << message unless ok
      ok
    end

    # Maps each required spec (a list of alternatives) to a distinct call, honouring order when ordered.
    # Backtracking search; cases have a handful of calls, so it's cheap. Returns the call indexes or nil.
    def assign(pred, spec_i = 0, used = [], min_index = 0)
      alts = @case.alternatives
      return used if spec_i == alts.size

      @t.calls.each_with_index do |call, ci|
        next if used.include?(ci) || (ordered? && ci < min_index)
        next unless alts[spec_i].any? { |spec| pred.call(spec, call) }

        found = assign(pred, spec_i + 1, used + [ci], ci + 1)
        return found if found
      end
      nil
    end

    def args_match?(spec, call)
      input = (call.input || {}).stringify_keys
      (spec["args"] || {}).all? { |k, m| Matcher.build(m).match?(input[k], present: input.key?(k)) }
    end

    def outcome_match?(spec, call)
      expected = spec.fetch("outcome", "ok")
      return true if expected == "any"
      return call.ok? if expected == "ok"

      expected.is_a?(Hash) && !call.ok? && call.error_code == expected["error"]
    end

    def hygiene
      problems = []
      forbidden = @t.calls.map(&:name) & @case.forbidden_tools
      problems << "forbidden tool called: #{forbidden.join(', ')}" if forbidden.any?
      if @case.max_calls && @t.calls.size > @case.max_calls
        problems << "#{@t.calls.size} tool calls, at most #{@case.max_calls} allowed"
      end
      failed = @t.calls.reject(&:ok?).map { |c| [c.name, c.input] }
      repeats = failed.tally.select { |_, n| n > 1 }.keys
      problems << "failed call repeated unchanged: #{repeats.map(&:first).join(', ')}" if repeats.any?
      problems.each { |p| @failures << p }
      problems.empty?
    end

    def required_desc = @case.alternatives.map { |alts| alts.map { |s| s["name"] }.join("|") }.join(" -> ")
    def called_desc = @t.calls.map(&:name).join(" -> ").presence || "nothing"

    def arg_mismatch_desc
      @case.alternatives.flatten.filter_map do |spec|
        same = @t.calls.select { |c| c.name == spec["name"] }
        next if same.empty? || same.any? { |c| args_match?(spec, c) }

        bad = (spec["args"] || {}).filter_map do |k, m|
          matcher = Matcher.build(m)
          vals = same.map { |c| (c.input || {}).stringify_keys[k] }
          "#{k} #{matcher.describe}, got #{vals.map(&:to_json).uniq.join(' / ')}" unless same.any? { |c| matcher.match?(c.input.stringify_keys[k], present: c.input.stringify_keys.key?(k)) }
        end
        "#{spec['name']}(#{bad.join('; ')})"
      end.join(", ")
    end

    def outcome_desc
      @t.calls.map { |c| "#{c.name}=#{c.ok? ? 'ok' : c.error_code}" }.join(", ")
    end
  end
end

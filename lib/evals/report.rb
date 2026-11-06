module Evals
  # Writes evals/results/<date>.json (live) or <date>.offline.json, a matching .md summary, and prints the table.
  class Report
    # USD per million tokens (claude-api skill pricing table). Cache writes 1.25x input, reads 0.1x input.
    PRICES = { "claude-opus-5-5" => [4.0, 20.0], "claude-sonnet-5-5" => [2.0, 10.0], "claude-haiku-4-5" => [1.0, 5.0] }.freeze

    def initialize(mode:, cases:, results:, meta: {})
      @mode = mode
      @cases = cases
      @results = results
      @meta = meta
    end

    def self.cost(model, usage)
      inp, out = PRICES[model.to_s] || (return nil)
      u = usage.transform_keys(&:to_s)
      ((u["input_tokens"].to_i * inp) + (u["output_tokens"].to_i * out) +
        (u["cache_creation_input_tokens"].to_i * inp * 1.25) + (u["cache_read_input_tokens"].to_i * inp * 0.1)) / 1_000_000.0
    end

    def summary
      by_tag = TAGS.to_h do |tag|
        rs = @results.select { |r| r.kase.tags.include?(tag) }
        [tag, { "cases" => rs.size, "passed" => rs.count(&:pass) }]
      end
      s = { "cases" => @results.size, "passed" => @results.count(&:pass), "by_tag" => by_tag }
      if @mode == "live"
        graded = @results.select { |r| r.status == "graded" }
        s["errors"] = @results.size - graded.size
        s["by_dimension"] = Grader::DIMENSIONS.to_h { |d| [d, graded.count { |r| r.grade.dimensions[d] }] }
        judged = graded.select { |r| r.judge&.dig("status") == "ok" }
        s["judge"] = { "judged" => judged.size, "passed" => judged.count { |r| r.judge["verdict"] == "pass" } } if @meta["judge_model"]
        usage = graded.map { |r| r.transcript.meta["usage"] || {} }
        s["usage"] = %w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].to_h { |k| [k, usage.sum { |u| u[k.to_sym].to_i + u[k].to_i }] }
        s["estimated_cost_usd"] = self.class.cost(@meta["model"], s["usage"])&.round(4)
      else
        s["oracle_passed"] = @results.count { |r| r.oracle&.pass }
        s["null_rejected"] = @results.count { |r| r.null && !r.null.pass }
        s["replays_checked"] = @results.count(&:replay)
      end
      s
    end

    def as_json(*)
      { "mode" => @mode, "generated_at" => Time.now.utc.iso8601, "as_of" => AS_OF.iso8601, **@meta,
        "summary" => summary, "cases" => @results.map(&:as_json) }
    end

    def table
      s = summary
      rows = TAGS.map { |t| [t, s["by_tag"][t]["cases"], s["by_tag"][t]["passed"]] }.reject { |_, n, _| n.zero? }
      out = +"| Tag | Cases | Passed | Rate |\n| --- | ---: | ---: | ---: |\n"
      rows.each { |t, n, p| out << "| #{t} | #{n} | #{p} | #{pct(p, n)} |\n" }
      out << "| **all** | **#{s['cases']}** | **#{s['passed']}** | **#{pct(s['passed'], s['cases'])}** |\n"
      if @mode == "live"
        graded = s["cases"] - s["errors"]
        out << "\n| Dimension | Passed |\n| --- | ---: |\n"
        s["by_dimension"].each { |d, n| out << "| #{d} | #{n}/#{graded} |\n" }
        out << "\nAPI errors (not graded): #{s['errors']}. Estimated cost: #{s['estimated_cost_usd'] ? format('$%.2f', s['estimated_cost_usd']) : 'n/a'}.\n"
        out << "Judge (#{@meta['judge_model']}): #{s['judge']['passed']}/#{s['judge']['judged']} pass.\n" if s["judge"]
      else
        out << "\nOracle trajectories passing: #{s['oracle_passed']}/#{s['cases']}. " \
               "Empty transcript rejected: #{s['null_rejected']}/#{s['cases']}. Replays graded: #{s['replays_checked']}.\n"
      end
      failing = @results.reject(&:pass)
      if failing.any?
        out << "\nFailing cases:\n"
        failing.each do |r|
          why = r.respond_to?(:problems) ? r.problems : (r.grade&.failures || [r.error])
          out << "- `#{r.kase.id}`: #{Array(why).join('; ')}\n"
        end
      end
      out
    end

    def write(dir = RESULTS_DIR, date: Date.current.iso8601)
      dir = Pathname(dir)
      dir.mkpath
      base = @mode == "live" ? date : "#{date}.offline"
      json = dir.join("#{base}.json")
      json.write("#{JSON.pretty_generate(as_json)}\n")
      md = dir.join("#{base}.md")
      md.write("# Evals: #{@mode}, #{date}\n\nSeed data as of #{AS_OF.iso8601}#{", model #{@meta['model']}" if @meta['model']}.\n\n#{table}")
      [json, md]
    end

    private

    def pct(p, n) = n.zero? ? "-" : format("%.0f%%", 100.0 * p / n)
  end
end

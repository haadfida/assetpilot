require "optparse"

module Evals
  # bin/evals [--offline | --live] [--judge] [--only ID,ID] [--tag TAG] [--out DIR] [--no-write]
  #
  # Mode: --live needs ANTHROPIC_API_KEY. Without a key the default is --offline; with one it is --live.
  # Exit status: 0 when every case passes, 1 otherwise (live: any deterministic failure or API error).
  module Cli
    module_function

    def run(argv, out: $stdout, err: $stderr, env: ENV)
      opts = { write: true, out: RESULTS_DIR }
      OptionParser.new do |o|
        o.banner = "Usage: bin/evals [options]"
        o.on("--offline", "Validate cases against the seed data and tool schemas (default without a key)") { opts[:mode] = "offline" }
        o.on("--live", "Run every case through Agent::Runner against the Claude API (needs ANTHROPIC_API_KEY)") { opts[:mode] = "live" }
        o.on("--judge", "Live only: also grade answer quality with an LLM judge (#{Judge::DEFAULT_MODEL}, EVAL_JUDGE_MODEL)") { opts[:judge] = true }
        o.on("--only IDS", "Comma-separated case ids") { |v| opts[:only] = v.split(",").map(&:strip) }
        o.on("--tag TAG", "Only cases with this tag") { |v| opts[:tag] = v }
        o.on("--out DIR", "Results directory (default evals/results)") { |v| opts[:out] = Pathname(v) }
        o.on("--no-write", "Print the summary without writing result files") { opts[:write] = false }
      end.parse!(argv)

      key = env["ANTHROPIC_API_KEY"].presence
      mode = opts[:mode] || (key ? "live" : "offline")
      if mode == "live" && !key
        err.puts "Live mode needs ANTHROPIC_API_KEY. Run without --live for the offline checks."
        return 2
      end
      if opts[:judge] && mode != "live"
        err.puts "--judge only applies to live runs; ignoring it in offline mode."
      end

      cases = Evals.load_cases
      cases = cases.select { |c| opts[:only].include?(c.id) } if opts[:only]
      cases = cases.select { |c| c.tags.include?(opts[:tag]) } if opts[:tag]
      if cases.empty?
        err.puts "No cases selected."
        return 2
      end

      report =
        if mode == "live"
          config = Agent::Config.current
          judge = opts[:judge] ? Judge.new(api_key: key) : nil
          err.puts "Live evals: #{cases.size} cases on #{config.model} (effort #{config.effort})#{", judge #{judge.model}" if judge}. This calls the Claude API and costs money."
          results = Live.new(cases, api_key: key, config: config, judge: judge).run
          Report.new(mode: "live", cases: cases, results: results,
                     meta: { "model" => config.model, "effort" => config.effort, "judge_model" => judge&.model, "git_sha" => git_sha }.compact)
        else
          results = Validator.new(cases).run
          Report.new(mode: "offline", cases: cases, results: results, meta: { "git_sha" => git_sha }.compact)
        end

      out.puts report.table
      if opts[:write]
        paths = report.write(opts[:out])
        out.puts "\nWrote #{paths.map { |p| p.relative_path_from(Rails.root) rescue p }.join(' and ')}"
      end
      ok = report.summary["passed"] == cases.size
      out.puts(ok ? "\n#{mode.upcase} EVALS PASSED" : "\n#{mode.upcase} EVALS FAILED")
      ok ? 0 : 1
    rescue Case::Invalid, OptionParser::ParseError => e
      err.puts e.message
      2
    rescue Live::Abort => e
      err.puts "Aborted: #{e.message}"
      1
    end

    def git_sha
      sha = `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip
      sha.presence
    end
  end
end

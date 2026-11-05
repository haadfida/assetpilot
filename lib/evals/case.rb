module Evals
  # One line of evals/cases.jsonl. Field reference (see also the README's Evals section):
  #
  #   id               unique slug
  #   prompt           the user message
  #   tags             subset of Evals::TAGS
  #   refs             {assets|people|services|locations: {ref => "exists"|"missing"|"ambiguous"}}: names the
  #                    case relies on, checked against the seed data offline
  #   expected_tools   {order: "ordered"|"unordered", calls: [call spec], forbidden?: [tool], max_calls?: n}
  #                    call spec: {name, args?: {arg => matcher}, outcome?: "ok"|"any"|{"error": code}}
  #                    or {any_of: [call spec, ...]}. Extra read-only calls are allowed; mutating tools not
  #                    named in a call spec are forbidden unless `forbidden` is given explicitly.
  #   expected_outcome {run?: "succeeded", db?: [db assertion]} (db is required when a mutating tool is expected;
  #                    cases without one get an implicit {"type": "unchanged"})
  #   answer           {includes: [regex]}: facts the final answer must state (case-insensitive)
  #   judge            optional rubric text for --judge
  #   oracle           {calls: [{name, input}], answer}: a reference trajectory; offline mode runs it through
  #                    the real tools and the grader, and it must pass
  #   replay           optional db/replays slug whose recorded trajectory must also pass
  class Case
    class Invalid < StandardError; end

    REF_KINDS = %w[assets people services locations].freeze
    REF_STATES = %w[exists missing ambiguous].freeze
    KEYS = %w[id prompt tags refs expected_tools expected_outcome answer judge oracle replay notes].freeze

    attr_reader :raw, :line

    def self.load_file(path)
      Pathname(path).each_line.with_index(1).filter_map do |text, line|
        next if text.strip.empty? || text.lstrip.start_with?("//")

        new(JSON.parse(text), line: line)
      rescue JSON::ParserError => e
        raise Invalid, "#{path}:#{line}: invalid JSON (#{e.message.lines.first.strip})"
      end
    end

    def initialize(raw, line: nil)
      @raw = raw
      @line = line
    end

    def id = raw["id"]
    def prompt = raw["prompt"]
    def tags = Array(raw["tags"])
    def refs = raw["refs"] || {}
    def expected_tools = raw["expected_tools"] || {}
    def order = expected_tools.fetch("order", "ordered")
    def call_specs = Array(expected_tools["calls"])
    def max_calls = expected_tools["max_calls"]
    def expected_run_status = (raw["expected_outcome"] || {}).fetch("run", "succeeded")
    def answer_patterns = Array((raw["answer"] || {})["includes"])
    def judge_rubric = raw["judge"]
    def oracle = raw["oracle"] || {}
    def replay = raw["replay"]

    # Each required call as a list of alternatives.
    def alternatives = call_specs.map { |spec| spec["any_of"] || [spec] }

    def expected_tool_names = alternatives.flatten.map { |s| s["name"] }.uniq

    def mutating_expected? = expected_tool_names.any? { |n| Tools::Registry.fetch(n)&.mutating? }

    def forbidden_tools
      return Array(expected_tools["forbidden"]) if expected_tools.key?("forbidden")

      Tools::Registry::TOOLS.select(&:mutating?).map(&:tool_name) - expected_tool_names
    end

    def db_assertions
      explicit = (raw["expected_outcome"] || {})["db"]
      explicit.presence || [{ "type" => "unchanged" }]
    end

    def to_s = "#{id} (line #{line})"
  end
end

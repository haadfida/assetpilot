module Evals
  # Argument and field matchers used by cases.
  #
  #   "AP-00502"                       bare literal: exact (JSON equality; strings compare exactly)
  #   {"exact": 1}                     exact
  #   {"regex": "^(DB-Server|AP-00502)$", "flags": "i"}   string match (non-strings never match)
  #   {"subset": ["AP-00502"]}         array: every listed element is present; object: every listed key matches
  #   {"set": ["AP-00502", "AP-00503"]}  array with exactly these elements, any order
  #   {"absent": true}                 the argument must not be given
  #
  # A matcher hash has exactly one of those keys (plus "flags" for regex); anything else is a literal object.
  class Matcher
    KINDS = %w[exact regex subset set absent].freeze

    class Invalid < StandardError; end

    attr_reader :kind, :expected

    def self.build(spec)
      if spec.is_a?(Hash) && (spec.keys - ["flags"]).size == 1 && KINDS.include?((spec.keys - ["flags"]).first)
        kind = (spec.keys - ["flags"]).first
        new(kind, spec[kind], flags: spec["flags"])
      else
        new("exact", spec)
      end
    end

    def initialize(kind, expected, flags: nil)
      @kind = kind
      @expected = expected
      @flags = flags.to_s
      compile!
    end

    def absent? = kind == "absent"

    # `present` is false when the argument was not given at all.
    def match?(actual, present: true)
      return !present if absent?
      return false unless present

      case kind
      when "exact" then normalize(actual) == normalize(expected)
      when "regex" then actual.is_a?(String) && @regex.match?(actual)
      when "subset" then subset?(actual)
      when "set" then actual.is_a?(Array) && normalize(actual).tally == normalize(expected).tally
      end
    end

    def describe
      case kind
      when "regex" then "/#{expected}/#{@flags}"
      when "absent" then "(absent)"
      else "#{kind} #{expected.to_json}"
      end
    end

    # Literal values this matcher can be checked against a JSON schema with (offline validation).
    def literal_values
      case kind
      when "exact" then [expected]
      when "subset", "set" then expected.is_a?(Array) ? expected : []
      else []
      end
    end

    private

    def compile!
      case kind
      when "regex"
        raise Invalid, "regex matcher needs a string" unless expected.is_a?(String)
        raise Invalid, "unknown regex flags #{@flags.inspect}" unless @flags.match?(/\A[imx]*\z/)

        opts = 0
        opts |= Regexp::IGNORECASE if @flags.include?("i")
        opts |= Regexp::MULTILINE if @flags.include?("m")
        opts |= Regexp::EXTENDED if @flags.include?("x")
        @regex = Regexp.new(expected, opts)
      when "subset"
        raise Invalid, "subset matcher needs an array or object" unless expected.is_a?(Array) || expected.is_a?(Hash)
      when "set"
        raise Invalid, "set matcher needs an array" unless expected.is_a?(Array)
      when "absent"
        raise Invalid, "absent matcher must be {\"absent\": true}" unless expected == true
      end
    rescue RegexpError => e
      raise Invalid, "regex #{expected.inspect} does not compile: #{e.message}"
    end

    def subset?(actual)
      case expected
      when Array then actual.is_a?(Array) && normalize(expected).all? { |e| normalize(actual).include?(e) }
      when Hash
        actual.is_a?(Hash) && expected.all? do |k, v|
          actual = actual.stringify_keys
          Matcher.build(v).match?(actual[k.to_s], present: actual.key?(k.to_s))
        end
      end
    end

    def normalize(value) = JSON.parse(JSON.generate(value))
  end
end

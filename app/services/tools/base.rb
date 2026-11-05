# A tool the agent can call. Each subclass declares a name, a description that says *when* to call
# it, and a JSON schema; `perform` does the work with plain ActiveRecord.
#
# `Tools::X.call(input)` never raises: it returns
#   { "ok" => true,  "data"  => {...} }
#   { "ok" => false, "error" => { "code" => "...", "message" => "...", "details" => {...} } }
# so a bad input or a failed mutation becomes an `is_error` tool_result the model can recover from.
#
# The schema is the single source of truth. The model gets it with `strict: true`, minus the
# keywords strict tool use does not support (numeric bounds, string/array length); the full schema,
# bounds included, is enforced here before `perform` runs. That also covers inputs that arrive
# unvalidated because the tools are declared with `eager_input_streaming: true`.
module Tools
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      super(message)
      @code = code
      @details = details
    end
  end

  class Base
    STRICT_UNSUPPORTED = %w[minimum maximum exclusiveMinimum exclusiveMaximum multipleOf
                            minLength maxLength minItems maxItems uniqueItems pattern].freeze

    class << self
      attr_reader :tool_name, :description, :input_schema

      def tool(name, description:, input_schema:)
        @tool_name = name
        @description = description.squish
        @input_schema = input_schema.deep_stringify_keys.freeze
      end

      # Tool definition for the Messages API.
      def definition
        { name: tool_name, description: description, input_schema: wire_schema,
          strict: true, eager_input_streaming: true }
      end

      def wire_schema = strip_unsupported(input_schema)

      def schemer = @schemer ||= JSONSchemer.schema(input_schema)

      def mutating? = false

      def call(input) = new.execute(input)

      private

      def strip_unsupported(node)
        case node
        when Hash then node.except(*STRICT_UNSUPPORTED).transform_values { |v| strip_unsupported(v) }
        when Array then node.map { |v| strip_unsupported(v) }
        else node
        end
      end
    end

    def execute(input)
      unless input.is_a?(Hash)
        return failure("invalid_input", "Tool input must be a JSON object", received: input.to_s.first(500))
      end

      input = input.deep_stringify_keys
      problems = self.class.schemer.validate(input).map { |e| { pointer: e["data_pointer"].presence || "/", error: e["error"] } }
      return failure("invalid_input", "Input does not match the #{self.class.tool_name} schema", problems: problems) if problems.any?

      { "ok" => true, "data" => perform(input).as_json }
    rescue Tools::Error => e
      failure(e.code, e.message, e.details)
    rescue ActiveRecord::RecordInvalid => e
      failure("validation_failed", e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      Rails.logger.error("[tools] #{self.class.tool_name} failed: #{e.class}: #{e.message}")
      failure("internal_error", "The #{self.class.tool_name} tool failed unexpectedly")
    end

    private

    def perform(_input) = raise(NotImplementedError)

    def failure(code, message, details = {})
      { "ok" => false, "error" => { "code" => code, "message" => message, "details" => details.as_json } }
    end

    def today = Time.zone.today

    def parse_date!(value, field)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Tools::Error.new("invalid_input", "#{field} must be an ISO date (YYYY-MM-DD)", field => value)
    end

    # --- lookups shared by the tools -------------------------------------------------------

    # An asset by tag (case-insensitive), numeric id, or exact name.
    def find_asset!(ref)
      ref = ref.to_s.strip
      found = Asset.find_by("lower(tag) = ?", ref.downcase)
      found ||= Asset.find_by(id: ref) if ref.match?(/\A\d+\z/)
      found || unique!(Asset.where("lower(name) = ?", ref.downcase), "asset", ref) { |a| { tag: a.tag, name: a.name } }
    end

    # A person by email, numeric id, or name (exact first, then a unique partial match).
    def find_person!(ref)
      ref = ref.to_s.strip
      found = Person.find_by("lower(email) = ?", ref.downcase)
      found ||= Person.find_by(id: ref) if ref.match?(/\A\d+\z/)
      return found if found

      exact = Person.where("lower(name) = ?", ref.downcase)
      scope = exact.exists? ? exact : Person.where("name ILIKE ?", "%#{Person.sanitize_sql_like(ref)}%")
      unique!(scope, "person", ref) { |p| { name: p.name, email: p.email } }
    end

    # A service by name (case-insensitive) or numeric id.
    def find_service!(ref)
      ref = ref.to_s.strip
      found = Service.find_by("lower(name) = ?", ref.downcase)
      found ||= Service.find_by(id: ref) if ref.match?(/\A\d+\z/)
      found || unique!(Service.where("name ILIKE ?", "%#{Service.sanitize_sql_like(ref)}%"), "service", ref) do |s|
        { name: s.name }
      end
    end

    def unique!(scope, kind, ref, &describe)
      matches = scope.order(:id).limit(6).to_a
      raise Tools::Error.new("not_found", "No #{kind} matches #{ref.inspect}", query: ref) if matches.empty?
      return matches.first if matches.one?

      raise Tools::Error.new("ambiguous", "#{matches.size}#{'+' if matches.size > 5} #{kind.pluralize} match #{ref.inspect}; be more specific",
                             query: ref, candidates: matches.first(5).map(&describe))
    end

    def person_brief(p) = p && { "name" => p.name, "email" => p.email, "department" => p.department }

    def checkout_brief(c)
      return nil unless c

      overdue_days = c.due_at < Time.current ? ((Time.current - c.due_at) / 1.day).floor : 0
      { "person" => c.person.name, "email" => c.person.email, "out_at" => c.out_at.iso8601,
        "due_at" => c.due_at.iso8601, "overdue" => c.due_at < Time.current, "days_overdue" => overdue_days }
    end

    def asset_brief(a, checkout: nil)
      {
        "tag" => a.tag, "name" => a.name, "category" => a.category, "status" => a.status,
        "location" => a.location&.name, "custodian" => a.custodian&.name,
        "warranty_until" => a.warranty_until&.iso8601,
        "warranty_expired" => a.warranty_until.present? && a.warranty_until < today
      }.tap { |h| h["checkout"] = checkout_brief(checkout) if checkout }
    end
  end
end

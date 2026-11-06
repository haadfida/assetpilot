module Evals
  # Database-state assertions for mutating cases, evaluated after a case runs against the snapshot taken
  # before it. Field values in an assertion are Evals::Matcher specs.
  #
  #   {"type": "unchanged", "tables"?: ["checkouts", "maintenance_tasks", "assets"]}
  #   {"type": "asset_status", "asset": "AP-00014", "equals": "available"}
  #   {"type": "open_checkout", "asset": "AP-00014", "person": null}            no open checkout
  #   {"type": "open_checkout", "asset": "AP-00030", "person": "Leon West", "due_on"?: "2026-11-20"}
  #   {"type": "checkouts_created", "count": 1, "asset"?: m, "asset_name"?: m, "person"?: m, "due_on"?: m}
  #   {"type": "checkouts_closed", "count": 1, "asset"?: m}
  #   {"type": "maintenance_created", "count": 3, "assets"?: m (array of tags), "kind"?: m, "due_on"?: m}
  class DbState
    TYPES = %w[unchanged asset_status open_checkout checkouts_created checkouts_closed maintenance_created].freeze
    TABLES = %w[assets checkouts maintenance_tasks].freeze
    FIELDS = {
      "unchanged" => [[], %w[tables]],
      "asset_status" => [%w[asset equals], []],
      "open_checkout" => [%w[asset person], %w[due_on]],
      "checkouts_created" => [%w[count], %w[asset asset_name person due_on]],
      "checkouts_closed" => [%w[count], %w[asset]],
      "maintenance_created" => [%w[count], %w[assets kind due_on]]
    }.freeze

    Result = Struct.new(:assertion, :pass, :detail, keyword_init: true) do
      def as_json(*) = { "assertion" => assertion, "pass" => pass, "detail" => detail }
    end

    attr_reader :rows

    def self.snapshot = new

    def initialize
      @rows = {
        "assets" => Asset.order(:id).pluck(:id, :tag, :status, :custodian_id, :location_id),
        "checkouts" => Checkout.order(:id).pluck(:id, :asset_id, :person_id, :out_at, :due_at, :in_at),
        "maintenance_tasks" => MaintenanceTask.order(:id).pluck(:id, :asset_id, :kind, :due_on, :status)
      }
      @max_checkout = @rows["checkouts"].map(&:first).max || 0
      @max_task = @rows["maintenance_tasks"].map(&:first).max || 0
      @open_ids = @rows["checkouts"].select { |r| r[5].nil? }.map(&:first)
    end

    # Static shape check, used by the offline validator. Returns a list of problems.
    def self.problems(assertion)
      return ["db assertion must be an object"] unless assertion.is_a?(Hash)

      type = assertion["type"]
      return ["unknown db assertion type #{type.inspect}"] unless TYPES.include?(type)

      required, optional = FIELDS.fetch(type)
      out = required.reject { |k| assertion.key?(k) }.map { |k| "#{type}: missing #{k}" }
      out += (assertion.keys - required - optional - ["type"]).map { |k| "#{type}: unknown field #{k}" }
      out << "#{type}: count must be a non-negative integer" if assertion.key?("count") && !(assertion["count"].is_a?(Integer) && assertion["count"] >= 0)
      out += Array(assertion["tables"]).reject { |t| TABLES.include?(t) }.map { |t| "unchanged: unknown table #{t}" }
      (optional + required - %w[count tables person]).each do |k|
        Matcher.build(assertion[k]) if assertion.key?(k)
      rescue Matcher::Invalid => e
        out << "#{type}.#{k}: #{e.message}"
      end
      out
    end

    def evaluate(assertions) = assertions.map { |a| check(a) }

    def check(a)
      pass, detail = send("check_#{a['type']}", a)
      Result.new(assertion: a, pass: pass, detail: detail)
    rescue StandardError => e
      Result.new(assertion: a, pass: false, detail: "#{e.class}: #{e.message}")
    end

    private

    def m(spec) = Matcher.build(spec)

    def check_unchanged(a)
      now = self.class.new
      changed = Array(a["tables"].presence || TABLES).reject { |t| now.rows[t] == rows[t] }
      [changed.empty?, changed.empty? ? "no changes" : "changed: #{changed.join(', ')}"]
    end

    def check_asset_status(a)
      asset = Asset.find_by!(tag: a["asset"])
      [m(a["equals"]).match?(asset.status), "#{asset.tag} is #{asset.status}"]
    end

    def check_open_checkout(a)
      asset = Asset.find_by!(tag: a["asset"])
      open = asset.checkouts.open.includes(:person).first
      if a["person"].nil?
        return [open.nil?, open ? "open checkout to #{open.person.name}" : "no open checkout"]
      end
      return [false, "no open checkout"] unless open

      ok = m(a["person"]).match?(open.person.name) && (!a.key?("due_on") || m(a["due_on"]).match?(open.due_at.to_date.iso8601))
      [ok, "open checkout to #{open.person.name}, due #{open.due_at.to_date.iso8601}"]
    end

    def check_checkouts_created(a)
      created = Checkout.where("checkouts.id > ?", @max_checkout).includes(:asset, :person).order(:id).to_a
      matching = created.select do |c|
        field?(a, "asset", c.asset.tag) && field?(a, "asset_name", c.asset.name) &&
          field?(a, "person", c.person.name) && field?(a, "due_on", c.due_at.to_date.iso8601)
      end
      desc = created.map { |c| "#{c.asset.tag}->#{c.person.name} due #{c.due_at.to_date.iso8601}" }
      [matching.size == a["count"] && created.size == a["count"], "created #{created.size} (#{matching.size} matching): #{desc.join('; ').presence || 'none'}"]
    end

    def check_checkouts_closed(a)
      closed = Checkout.where(id: @open_ids).where.not(in_at: nil).includes(:asset).to_a
      matching = closed.select { |c| field?(a, "asset", c.asset.tag) }
      [matching.size == a["count"] && closed.size == a["count"], "closed #{closed.size}: #{closed.map { |c| c.asset.tag }.join(', ').presence || 'none'}"]
    end

    def check_maintenance_created(a)
      created = MaintenanceTask.where("maintenance_tasks.id > ?", @max_task).includes(:asset).order(:id).to_a
      ok = created.size == a["count"] &&
           created.all? { |t| field?(a, "kind", t.kind) && field?(a, "due_on", t.due_on.iso8601) } &&
           field?(a, "assets", created.map { |t| t.asset.tag })
      [ok, "created #{created.size}: #{created.map { |t| "#{t.asset.tag} #{t.kind} #{t.due_on.iso8601}" }.join('; ').presence || 'none'}"]
    end

    def field?(a, key, value) = !a.key?(key) || m(a[key]).match?(value)
  end
end

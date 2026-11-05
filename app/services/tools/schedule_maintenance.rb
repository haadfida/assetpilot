module Tools
  class ScheduleMaintenance < Base
    MAX_ASSETS = 50
    MAX_DAYS = 365

    tool "schedule_maintenance",
         description: <<~TXT,
           Schedule one maintenance task of the given kind and due date for each listed asset. This changes the
           inventory: call it only when the user asks to schedule maintenance, inspections, repairs or similar
           work. To act on "all assets matching X", call search_assets first and pass the tags. All-or-nothing on
           unknown assets: if any asset cannot be found nothing is scheduled. Retired assets and assets that
           already have the same task scheduled on that date are skipped and reported.
         TXT
         input_schema: {
           type: "object",
           properties: {
             assets: { type: "array", minItems: 1, maxItems: MAX_ASSETS,
                       items: { type: "string", minLength: 1 },
                       description: "Asset tags (or ids / exact names), up to 50" },
             kind: { type: "string", enum: MaintenanceTask::KINDS },
             due_on: { type: "string", format: "date", description: "Due date, YYYY-MM-DD, today or later" }
           },
           required: %w[assets kind due_on],
           additionalProperties: false
         }

    def self.mutating? = true
    def self.destructive? = false # only adds tasks, never overwrites

    private

    def perform(input)
      due_on = parse_date!(input["due_on"], "due_on")
      unless due_on >= today && due_on <= today + MAX_DAYS
        raise Tools::Error.new("invalid_due_date", "due_on must be between today and #{MAX_DAYS} days out",
                               due_on: due_on.iso8601, today: today.iso8601)
      end

      refs = input["assets"].map(&:strip).uniq
      resolved = {}
      unknown = []
      refs.each do |ref|
        resolved[ref] = find_asset!(ref)
      rescue Tools::Error => e
        unknown << { ref: ref, code: e.code, message: e.message }
      end
      raise Tools::Error.new("not_found", "#{unknown.size} of #{refs.size} assets could not be resolved; nothing was scheduled",
                             unresolved: unknown) if unknown.any?

      scheduled = []
      skipped = []
      MaintenanceTask.transaction do
        resolved.values.uniq.each do |asset|
          if asset.status == "retired"
            skipped << { tag: asset.tag, reason: "retired" }
          elsif asset.maintenance_tasks.exists?(kind: input["kind"], due_on: due_on, status: %w[scheduled in_progress])
            skipped << { tag: asset.tag, reason: "already_scheduled" }
          else
            task = asset.maintenance_tasks.create!(kind: input["kind"], due_on: due_on, status: "scheduled")
            scheduled << { task_id: task.id, tag: asset.tag, name: asset.name }
          end
        end
      end

      { kind: input["kind"], due_on: due_on.iso8601, scheduled_count: scheduled.size, scheduled: scheduled, skipped: skipped }
    end
  end
end

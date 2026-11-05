module Tools
  class SummarizeFleet < Base
    EXPIRING_DAYS = 90

    tool "summarize_fleet",
         description: <<~TXT,
           Aggregate statistics for the whole inventory or one location: asset counts by status, category and
           location, warranty expired / expiring in 90 days, open and overdue checkouts, scheduled and overdue
           maintenance, and services by criticality. Call this for overview questions ("summarize the fleet",
           "how healthy is our inventory") instead of paging through search_assets.
         TXT
         input_schema: {
           type: "object",
           properties: {
             location: { type: "string", description: "Optional location name (or part of it) to restrict the summary" }
           },
           required: [],
           additionalProperties: false
         }

    private

    def perform(input)
      assets = Asset.all
      if input["location"].present?
        locs = Location.where("name ILIKE ?", "%#{Location.sanitize_sql_like(input['location'])}%")
        raise Tools::Error.new("not_found", "No location matches #{input['location'].inspect}") unless locs.exists?

        assets = assets.where(location_id: locs.select(:id))
      end
      ids = assets.select(:id)
      open = Checkout.open.where(asset_id: ids)
      tasks = MaintenanceTask.where(asset_id: ids)

      {
        as_of: today.iso8601,
        scope: input["location"].presence || "all locations",
        total_assets: assets.count,
        by_status: assets.group(:status).count.sort.to_h,
        by_category: assets.group(:category).count.sort_by { |c, n| [-n, c] }.to_h,
        by_location: assets.left_joins(:location).group("locations.name").count
                           .sort_by { |l, n| [-n, l.to_s] }.to_h { |l, n| [l || "(none)", n] },
        warranty: { expired: assets.where(warranty_until: ...today).count,
                    expiring_within_90_days: assets.where(warranty_until: today..(today + EXPIRING_DAYS)).count },
        checkouts: { open: open.count, overdue: open.where(due_at: ...Time.current).count },
        maintenance: { scheduled: tasks.where(status: "scheduled").count,
                       in_progress: tasks.where(status: "in_progress").count,
                       overdue: tasks.where(status: %w[scheduled in_progress], due_on: ...today).count },
        services_by_criticality: input["location"].present? ? nil : Service.group(:criticality).count.sort.to_h
      }.compact
    end
  end
end

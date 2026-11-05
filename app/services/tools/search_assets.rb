module Tools
  class SearchAssets < Base
    MAX_LIMIT = 50

    tool "search_assets",
         description: <<~TXT,
           Search the asset inventory with optional filters. Call this whenever the user asks which or how many
           assets match some criteria (category, status, location, custodian, warranty state, overdue checkouts),
           or when you need asset tags before acting on several assets. Results are ordered by tag (by due date
           when overdue=true) and include the open checkout for checked-out assets. Dates are evaluated on the
           server's current date, returned as as_of.
         TXT
         input_schema: {
           type: "object",
           properties: {
             query: { type: "string", description: "Free text matched against asset name, tag and serial" },
             category: { type: "string", enum: Asset::CATEGORIES },
             status: { type: "string", enum: Asset::STATUSES },
             location: { type: "string", description: "Location name or part of it, e.g. Data-Center-1" },
             custodian: { type: "string", description: "Custodian name or email, partial match" },
             warranty: { type: "string", enum: %w[expired active], description: "Warranty state today" },
             warranty_expires_within_days: { type: "integer", minimum: 0, maximum: 3650,
                                             description: "Only assets whose warranty ends between today and today + N days" },
             overdue: { type: "boolean", description: "Only assets with an open checkout past its due date" },
             limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Max results (default 20, max 50)" }
           },
           required: [],
           additionalProperties: false
         }

    private

    def perform(input)
      scope = Asset.search(input["query"]).includes(:location, :custodian)
      scope = scope.where(category: input["category"]) if input["category"]
      scope = scope.where(status: input["status"]) if input["status"]
      if input["location"].present?
        # Subqueries, not joins: Asset.search uses unqualified column names.
        scope = scope.where(location_id: Location.where("name ILIKE ?", "%#{Location.sanitize_sql_like(input['location'])}%").select(:id))
      end
      if input["custodian"].present?
        like = "%#{Person.sanitize_sql_like(input['custodian'])}%"
        scope = scope.where(custodian_id: Person.where("name ILIKE :q OR email ILIKE :q", q: like).select(:id))
      end
      scope = scope.where(warranty_until: ...today) if input["warranty"] == "expired"
      scope = scope.where(warranty_until: today..) if input["warranty"] == "active"
      if (days = input["warranty_expires_within_days"])
        scope = scope.where(warranty_until: today..(today + days))
      end

      checkouts = Checkout.open.includes(:person)
      if input["overdue"]
        scope = scope.joins(:checkouts).merge(Checkout.overdue).reorder("checkouts.due_at")
      else
        scope = scope.order(:tag)
      end

      limit = input.fetch("limit", 20)
      total = scope.count
      assets = scope.limit(limit).to_a
      open_by_asset = checkouts.where(asset_id: assets.map(&:id)).index_by(&:asset_id)

      {
        as_of: today.iso8601, total: total, returned: assets.size, truncated: total > assets.size,
        assets: assets.map { |a| asset_brief(a, checkout: open_by_asset[a.id]) }
      }
    end
  end
end

module Tools
  # Wraps the M1 recursive-CTE ::ImpactAnalysis with name/tag resolution and a compact result.
  class ImpactAnalysis < Base
    LIST_CAP = 25

    tool "impact_analysis",
         description: <<~TXT,
           Find everything that would be affected if an asset or service failed: every service and asset that
           transitively depends on or runs on it (with hop distance), and the people to notify (service owners
           and asset custodians). Call this for "what breaks if X goes down", outage blast-radius, or
           "who is affected" questions. Lists are capped at 25 entries; counts are always complete.
         TXT
         input_schema: {
           type: "object",
           properties: {
             node_type: { type: "string", enum: %w[asset service] },
             node: { type: "string", minLength: 1, description: "Asset tag / id / exact name, or service name / id" },
             max_depth: { type: "integer", minimum: 1, maximum: ::ImpactAnalysis::HARD_MAX_DEPTH,
                          description: "Hops to follow (default 10, max 25)" }
           },
           required: %w[node_type node],
           additionalProperties: false
         }

    private

    def perform(input)
      root = input["node_type"] == "asset" ? find_asset!(input["node"]) : find_service!(input["node"])
      r = ::ImpactAnalysis.call(type: input["node_type"], id: root.id,
                                max_depth: input.fetch("max_depth", ::ImpactAnalysis::DEFAULT_MAX_DEPTH))
      owners = r.services.to_h { |s, _| [s.id, s.owner] }

      {
        root: { type: input["node_type"], name: root.name, tag: root.try(:tag), criticality: root.try(:criticality) }.compact,
        max_depth: r.max_depth,
        counts: { services: r.services.size, assets: r.assets.size, people: r.people.size },
        services_by_criticality: Service::CRITICALITIES.reverse.to_h { |c| [c, r.services.count { |s, _| s.criticality == c }] },
        assets_by_category: r.assets.map { |a, _| a.category }.tally.sort.to_h,
        services: r.services.first(LIST_CAP).map do |s, depth|
          { name: s.name, criticality: s.criticality, depth: depth, owner: owners[s.id]&.name }
        end,
        assets: r.assets.first(LIST_CAP).map do |a, depth|
          { tag: a.tag, name: a.name, category: a.category, depth: depth, custodian: a.custodian&.name }
        end,
        people: r.people.first(LIST_CAP).map { |p| person_brief(p) },
        truncated: { services: r.services.size > LIST_CAP, assets: r.assets.size > LIST_CAP, people: r.people.size > LIST_CAP }
      }
    end
  end
end

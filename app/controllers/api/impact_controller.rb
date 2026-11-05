module Api
  class ImpactController < BaseController
    def show
      r = ImpactAnalysis.call(type: params[:type], id: params[:id],
                              max_depth: params[:max_depth].presence || ImpactAnalysis::DEFAULT_MAX_DEPTH)
      render json: {
        root: { type: r.root.class.name, id: r.root.id, name: r.root.name },
        max_depth: r.max_depth,
        services: r.services.map { |s, d| s.slice(:id, :name, :criticality, :owner_id).merge(depth: d) },
        assets: r.assets.map { |a, d| a.slice(:id, :tag, :name, :category, :status, :custodian_id).merge(depth: d) },
        people: r.people.map { |p| p.slice(:id, :name, :email, :department) },
        counts: { services: r.services.size, assets: r.assets.size, people: r.people.size },
        edges: edges(r)
      }
    rescue ImpactAnalysis::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    end

    private

    # The dependency edges inside the impacted subgraph (root included), so clients can draw it.
    # "source depends on / runs on target", the same direction as the dependencies table.
    def edges(r)
      keys = [[r.root.class.name, r.root.id]] + r.services.map { |s, _| ["Service", s.id] } + r.assets.map { |a, _| ["Asset", a.id] }
      by_type = keys.group_by(&:first).transform_values { |v| v.map(&:last) }
      scope = by_type.map { |type, ids| Dependency.where(source_type: type, source_id: ids) }.reduce(:or)
      set = keys.to_set
      scope.pluck(:source_type, :source_id, :target_type, :target_id, :kind)
           .select { |st, si, tt, ti, _| set.include?([st, si]) && set.include?([tt, ti]) }
           .map { |st, si, tt, ti, kind| { source: { type: st, id: si }, target: { type: tt, id: ti }, kind: kind } }
    end
  end
end

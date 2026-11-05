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
        counts: { services: r.services.size, assets: r.assets.size, people: r.people.size }
      }
    rescue ImpactAnalysis::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    end
  end
end

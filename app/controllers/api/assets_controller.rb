module Api
  class AssetsController < BaseController
    FILTERS = %w[status category location_id custodian_id].freeze

    def index
      scope = Asset.search(params[:q])
      FILTERS.each { |f| scope = scope.where(f => params[f]) if params[f].present? }
      scope = scope.warranty_expiring_before(Date.parse(params[:warranty_before])) if params[:warranty_before].present?
      scope = scope.includes(:location, :custodian).order(:tag)
      records, meta = paginate(scope)
      render json: { data: records.map { |a| AssetSerializer.call(a) }, meta: meta }
    rescue Date::Error
      render json: { error: "bad_request", message: "invalid warranty_before" }, status: :bad_request
    end

    def show
      asset = Asset.includes(:location, :custodian, :maintenance_tasks).find(params[:id])
      open_checkout = asset.checkouts.open.includes(:person).first
      render json: { data: AssetSerializer.call(asset).merge(
        open_checkout: open_checkout && { id: open_checkout.id, person_id: open_checkout.person_id,
                                          person_name: open_checkout.person.name,
                                          out_at: open_checkout.out_at, due_at: open_checkout.due_at },
        maintenance_tasks: asset.maintenance_tasks.sort_by(&:due_on).map do |t|
          t.slice(:id, :due_on, :kind, :status)
        end
      ) }
    end
  end
end

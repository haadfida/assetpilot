module Api
  class PeopleController < BaseController
    def index
      scope = Person.order(:name)
      scope = scope.where(department: params[:department]) if params[:department].present?
      scope = scope.where("name ILIKE :q OR email ILIKE :q", q: "%#{Person.sanitize_sql_like(params[:q])}%") if params[:q].present?
      records, meta = paginate(scope)
      render json: { data: records.map { |p| p.slice(:id, :name, :email, :department) }, meta: meta }
    end

    def show
      p = Person.find(params[:id])
      render json: { data: p.slice(:id, :name, :email, :department).merge(
        custodied_asset_ids: p.custodied_assets.order(:id).pluck(:id),
        owned_service_ids: p.owned_services.order(:id).pluck(:id)
      ) }
    end
  end
end

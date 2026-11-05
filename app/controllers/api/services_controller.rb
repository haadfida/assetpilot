module Api
  class ServicesController < BaseController
    def index
      scope = Service.includes(:owner).order(:name)
      scope = scope.where(criticality: params[:criticality]) if params[:criticality].present?
      records, meta = paginate(scope)
      render json: { data: records.map { |s| serialize(s) }, meta: meta }
    end

    def show
      render json: { data: serialize(Service.includes(:owner).find(params[:id])) }
    end

    private

    def serialize(s)
      s.slice(:id, :name, :criticality, :owner_id).merge(owner_name: s.owner&.name)
    end
  end
end

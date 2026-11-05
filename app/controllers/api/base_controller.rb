module Api
  class BaseController < ApplicationController
    MAX_PER_PAGE = 100
    DEFAULT_PER_PAGE = 25

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: "not_found", message: e.message }, status: :not_found
    end

    private

    def page = [params[:page].to_i, 1].max
    def per_page = (params[:per_page].presence&.to_i || DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)

    def paginate(scope)
      total = scope.count
      records = scope.offset((page - 1) * per_page).limit(per_page)
      [records, { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }]
    end
  end
end

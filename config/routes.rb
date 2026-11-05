Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resources :assets, only: %i[index show]
    resources :people, only: %i[index show]
    resources :services, only: %i[index show]
    get "impact/:type/:id", to: "impact#show", as: :impact, constraints: { type: /asset|service/i, id: /\d+/ }
  end
end

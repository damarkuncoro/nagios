Rails.application.routes.draw do
  root "hosts#index"
  resources :hosts, only: [:index, :show] do
    member do
      post :recheck
      post :recheck_service
      post :acknowledge_service
      post :schedule_service_downtime
    end
  end

  get "/tactical", to: "tactical#index", as: :tactical
  get "/problems", to: "problems#index", as: :problems
  get "/statusmap", to: "statusmap#index", as: :statusmap
  get "/availability", to: "availability#index", as: :availability
  get "/summary", to: "summary#index", as: :summary
  get "/trends", to: "trends#index", as: :trends
  get "/process_info", to: "process_info#show", as: :process_info
  post "/process_info/toggle", to: "process_info#toggle", as: :toggle_process_info_feature
  post "/process_info/test_webhook", to: "process_info#test_webhook", as: :test_process_info_webhook
  get "/queue", to: "queue#index", as: :queue
  get "/configuration", to: "configuration#index", as: :configuration
  get "/perf_info", to: "perf_info#show", as: :perf_info

  resources :hostgroups, only: [:index]
  resources :servicegroups, only: [:index]
  resources :alerts, only: [:index]
  resources :downtimes, only: [:index, :destroy]
  resources :comments, only: [:index, :create, :destroy]

  namespace :api do
    namespace :v1 do
      get "/status", to: "statuses#index"
      get "/tactical", to: "statuses#tactical"
      get "/problems", to: "statuses#problems"
    end
  end
end

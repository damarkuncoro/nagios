Rails.application.routes.draw do
  root "hosts#index"
  resources :hosts, only: [:index, :show] do
    member do
      post :recheck
      post :recheck_service
      post :recheck_all_services
      post :acknowledge
      post :remove_acknowledgment
      post :acknowledge_service
      post :remove_service_acknowledgment
      post :schedule_downtime
      post :schedule_cluster_downtime
      post :schedule_service_downtime
      post :toggle_notifications
      post :toggle_checks
      post :toggle_service_notifications
      post :toggle_service_checks
      post :toggle_flap_detection
      post :toggle_service_flap_detection
      post :submit_passive_check
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
  post "/process_info/toggle_daemon", to: "process_info#toggle_daemon", as: :toggle_daemon
  post "/process_info/test_tcp_probe", to: "process_info#test_tcp_probe", as: :test_tcp_probe
  post "/process_info/execute_command", to: "process_info#execute_command", as: :execute_command
  get "/outages", to: "outages#index", as: :outages
  get "/queue", to: "queue#index", as: :queue
  get "/configuration", to: "configuration#index", as: :configuration
  post "/configuration/verify", to: "configuration#verify", as: :verify_configuration
  get "/perf_info", to: "perf_info#show", as: :perf_info

  resources :hostgroups, only: [:index]
  resources :servicegroups, only: [:index]
  resources :alerts, only: [:index]
  resources :notifications, only: [:index]
  resources :logs, only: [:index]
  resources :downtimes, only: [:index, :destroy]
  resources :comments, only: [:index, :create, :destroy]

  namespace :api do
    namespace :v1 do
      get "/status", to: "statuses#index"
      get "/tactical", to: "statuses#tactical"
      get "/problems", to: "statuses#problems"
      get "/queue", to: "statuses#queue"
      get "/availability", to: "statuses#availability"
      get "/objects", to: "objects#index"
      get "/archives", to: "archives#index"
    end
  end
end

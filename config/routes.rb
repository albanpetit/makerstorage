Rails.application.routes.draw do
  devise_for :users, skip: [ :sessions, :passwords, :registrations ]
  as :user do
    get "login", to: "users/sessions#new", as: :new_user_session
    post "login", to: "users/sessions#create", as: :user_session
    match "logout", to: "users/sessions#destroy", as: :destroy_user_session, via: Devise.mappings[:user].sign_out_via
    get "signup", to: "users/registrations#new", as: :new_user_registration
    post "signup", to: "users/registrations#create", as: :user_registration
    get "forgot-password", to: "users/passwords#new", as: :new_user_password
    post "forgot-password", to: "users/passwords#create", as: :user_password
    get "reset-password", to: "users/passwords#edit", as: :edit_user_password
    put "reset-password", to: "users/passwords#update", as: :update_user_password
  end

  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end
  # Organizations
  resources :organizations, only: [ :create, :destroy ] do
    member do
      post :switch
    end
  end

  # Inventory resources
  resources :parts, except: %i[new] do
    collection do
      post :import
      post :lookup
      post :bulk_move
      delete :bulk_destroy
    end

    resources :part_suppliers, only: %i[create update destroy] do
      member do
        post :set_preferred
      end
    end
  end

  resources :categories, only: %i[index create update destroy]

  resources :footprints, only: %i[index create update destroy]

  resources :tags, only: %i[index create update destroy]

  resources :storage_locations, only: %i[index create update destroy]

  resources :stock_movements, only: %i[index create] do
    get :export, on: :collection
  end

  get "scan", to: "scans#index", as: :scan
  post "scan/movements", to: "scans#create_movement", as: :scan_movements

  get "search", to: "search#index", as: :search

  resources :suppliers, only: %i[index create update destroy]

  get "alerts", to: "alerts#index"
  post "alerts/purchase_orders", to: "alerts#create_purchase_orders", as: :alert_purchase_orders
  patch "alerts/orders/:id/advance", to: "alerts#advance_order", as: :advance_alert_order

  resources :members, only: %i[index create update destroy]

  resource :settings, only: %i[show update] do
    post :reassign_ipns
  end

  resource :profile, only: %i[show update]

  root "dashboard#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

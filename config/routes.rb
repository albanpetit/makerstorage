Rails.application.routes.draw do
  # Active Storage's direct-upload endpoints accept a file from anyone holding a
  # CSRF token — no sign-in needed — and the app never uses them (uploads go
  # through the authenticated forms). Shadow them ahead of the engine's routes so
  # they can't be used to fill the disk.
  match "rails/active_storage/direct_uploads", to: proc { [ 404, {}, [] ] }, via: :all
  match "rails/active_storage/disk/:encoded_token", to: proc { [ 404, {}, [] ] }, via: :put

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

  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server.
  # Development only: in the test env Capybara serves the app on 127.0.0.1, and
  # this cross-origin hop makes Chrome block every Inertia XHR with CORS errors.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"

    constraints(host: "127.0.0.1") do
      get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
    end
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
      post :bulk_update_category
      post :bulk_update_status
      post :bulk_update_tags
      post :bulk_assign_supplier
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

  resources :storage_locations, only: %i[index create update destroy] do
    post :move_stock, on: :collection
  end

  resources :stock_movements, only: %i[index create] do
    get :export, on: :collection
  end

  get "scan", to: "scans#index", as: :scan
  post "scan/movements", to: "scans#create_movement", as: :scan_movements

  get "search", to: "search#index", as: :search

  # DigiKey account connection (3-legged OAuth) for the user-scoped Order API.
  get "oauth/digikey/authorize", to: "oauth/digikey#authorize", as: :oauth_digikey_authorize
  get "oauth/digikey/callback", to: "oauth/digikey#callback", as: :oauth_digikey_callback
  delete "oauth/digikey", to: "oauth/digikey#disconnect", as: :oauth_digikey

  resources :suppliers, only: %i[index create update destroy]

  # Purchase orders (supplier orders)
  resources :orders, only: %i[index show create update destroy] do
    member do
      patch :advance
      post :import_project
      post :push_to_cart
      post :assign_storage
    end
    collection do
      post :import_supplier_order
    end

    resources :order_lines, only: %i[create update destroy] do
      post :catalog, on: :collection
    end
  end

  # Project BOM availability checks
  resources :projects, only: %i[index show create destroy] do
    member do
      post :confirm
      post :create_purchase_orders
      post :build
    end

    resources :project_lines, only: %i[update destroy]
  end

  get "alerts", to: "alerts#index"
  post "alerts/purchase_orders", to: "alerts#create_purchase_orders", as: :alert_purchase_orders
  patch "alerts/orders/:id/advance", to: "alerts#advance_order", as: :advance_alert_order

  resources :members, only: %i[index create update destroy]

  resource :settings, only: %i[show update] do
    post :reassign_ipns
  end

  resource :profile, only: %i[show update]

  # Organization invitations addressed to the signed-in user.
  resources :invitations, only: [] do
    member do
      post :accept
      delete :decline
    end
  end

  root "dashboard#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (manifest linked in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"
end

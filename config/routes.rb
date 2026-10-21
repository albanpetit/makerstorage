Rails.application.routes.draw do
  # Active Storage's own routes are all public: direct uploads accept a file from
  # anyone holding a CSRF token (no sign-in needed), and blob links serve a file
  # to anyone who has the URL, forever. Shadow every one of them ahead of the
  # engine's routes; uploads go through the authenticated forms and files are
  # served by StoredFilesController to members of the owning organization.
  match "rails/active_storage/*path", to: proc { [ 404, {}, [] ] }, via: :all, format: false
  get "files/:signed_id/*filename", to: "stored_files#show", as: :stored_file, format: false

  devise_for :users, skip: [ :sessions, :passwords, :registrations, :confirmations ]
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
    get "confirm-email", to: "users/confirmations#show", as: :user_confirmation
    post "confirm-email", to: "users/confirmations#create", as: :resend_user_confirmation
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
      # Danger zone: empty the organization, or merge it into another one.
      post :reset
      post :merge
    end
  end

  # Inventory resources
  resources :parts, except: %i[new] do
    collection do
      post :import
      post :lookup
      post :rows
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

  # Technical parameters (Resistance, Tolerance…) and their category templates.
  resources :parameter_definitions, path: "parameters", only: %i[index create update destroy] do
    post :standard, on: :collection
  end

  resources :storage_locations, only: %i[index create update destroy] do
    post :move_stock, on: :collection
    post :add_bags, on: :member
  end

  resources :stock_movements, only: %i[index create] do
    get :export, on: :collection
  end

  # Stocktakes (cycle counts): count a zone, then adjust stock to the count.
  resources :stocktakes, only: %i[index show create destroy] do
    member do
      post :complete
      post :scan
      get :export
    end

    resources :stocktake_lines, only: %i[create update], path: "lines"
  end

  get "scan", to: "scans#index", as: :scan
  post "scan/movements", to: "scans#create_movement", as: :scan_movements
  post "scan/receipts", to: "scans#receive", as: :scan_receipts

  get "search", to: "search#index", as: :search

  # MCP server for Claude (claude.ai, Claude Desktop, Claude Code): read-only
  # inventory tools behind OAuth 2.1 (dynamic client registration + PKCE).
  post "mcp", to: "mcp#create", as: :mcp, format: false
  match "mcp", to: "mcp#method_not_allowed", via: %i[get delete], format: false
  get ".well-known/oauth-protected-resource(/*resource)", to: "oauth/metadata#protected_resource", format: false
  get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server", format: false
  post "oauth/register", to: "oauth/registrations#create", as: :oauth_register
  get "oauth/authorize", to: "oauth/authorizations#new", as: :oauth_authorize
  post "oauth/authorize", to: "oauth/authorizations#create"
  post "oauth/token", to: "oauth/tokens#create", as: :oauth_token
  post "oauth/revoke", to: "oauth/tokens#revoke", as: :oauth_revoke

  # KiCad HTTP library (KicadLibrary): the organization's parts in KiCad's
  # symbol chooser, behind the organization's KiCad token. KiCad appends the
  # API version to the root URL; the bare paths answer too.
  scope "kicad(/v1)", controller: :kicad_library, format: false, constraints: { id: /\d+/, category_id: /\d+/ } do
    get "/", action: :index, as: :kicad_library
    get "categories.json", action: :categories
    get "parts/category/:category_id.json", action: :category_parts
    get "parts/:id.json", action: :part
  end

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
  resources :projects, only: %i[index show create update destroy] do
    member do
      post :duplicate
      post :confirm
      post :reserve
      post :release
      post :create_purchase_orders
      post :build
    end

    resources :project_lines, only: %i[create update destroy]
    resources :project_files, path: "files", only: %i[create destroy] do
      post :import_bom, on: :collection
    end
    resource :github, controller: "project_github", only: %i[update destroy] do
      post :sync
    end
  end

  get "alerts", to: "alerts#index"
  post "alerts/purchase_orders", to: "alerts#create_purchase_orders", as: :alert_purchase_orders
  patch "alerts/orders/:id/advance", to: "alerts#advance_order", as: :advance_alert_order

  resources :members, only: %i[index create update destroy]

  resource :settings, only: %i[show update] do
    post :reassign_ipns
    get :reassign_ipns_preview
    post :kicad_token, action: :create_kicad_token
    delete :kicad_token, action: :destroy_kicad_token
  end

  # Organization backup: download the current organization, or restore an
  # archive into a new one.
  get "backup/export", to: "backups#export", as: :export_backup
  post "backup/import", to: "backups#import", as: :import_backup

  resource :profile, only: %i[show update]
  patch "profile/notifications/:id", to: "profiles#update_notifications", as: :profile_notifications
  delete "profile/connected_apps/:id", to: "profiles#revoke_connected_app", as: :profile_connected_app

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

  # Content-Security-Policy violation reports (report-only policy).
  post "csp-violations" => "csp_reports#create", as: :csp_reports

  # Render dynamic PWA files from app/views/pwa/* (manifest linked in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"
end

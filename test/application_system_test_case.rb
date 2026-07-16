require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    # Inertia's config.encrypt_history (config/initializers/inertia_rails.rb)
    # needs window.crypto.subtle, which Chrome only exposes in a secure context
    # (https, or the literal hostname "localhost"). The app here is served at the
    # docker-compose alias "rails-app" so the separate Selenium container can
    # reach it, which fails that check and leaves every Inertia visit hanging.
    # Telling Chrome to trust this one origin fixes that without touching the
    # encrypt_history setting itself.
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    } do |chrome_options|
      chrome_options.add_argument("--unsafely-treat-insecure-origin-as-secure=http://rails-app:#{ENV["CAPYBARA_SERVER_PORT"]}")
    end
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end

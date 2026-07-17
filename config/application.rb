require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Makerstorage
  # Build Action Mailer SMTP settings from environment variables so outgoing mail
  # is configured the same, provider-agnostic way in every environment. Returns
  # nil when SMTP_ADDRESS is unset, signalling that mail delivery isn't configured
  # (self-hosters set these to point at their own mail provider — see README).
  def self.smtp_settings_from_env
    return nil if ENV["SMTP_ADDRESS"].blank?

    settings = {
      address: ENV["SMTP_ADDRESS"],
      port:    ENV.fetch("SMTP_PORT", "587").to_i
    }
    settings[:domain] = ENV["SMTP_DOMAIN"] if ENV["SMTP_DOMAIN"].present?

    if ENV["SMTP_USERNAME"].present?
      settings[:user_name]      = ENV["SMTP_USERNAME"]
      settings[:password]       = ENV["SMTP_PASSWORD"]
      settings[:authentication] = ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym
    end

    # TLS mode: STARTTLS on 587 (default), implicit TLS on 465, or plain.
    case ENV.fetch("SMTP_TLS", "starttls").downcase
    when "ssl", "tls"           then settings[:tls] = true
    when "none", "off", "false" then settings[:enable_starttls_auto] = false
    else                             settings[:enable_starttls_auto] = true
    end

    settings
  end

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end

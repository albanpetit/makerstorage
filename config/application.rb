require_relative "boot"

require "rails"
# Every framework from "rails/all" except Action Mailbox and Action Text, which
# the app doesn't use: loading them only exposed their public ingress routes.
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

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

    # Use .presence throughout: values arriving from CI/Kamal are often set to an
    # empty string rather than left unset, and "" must fall back to the default.
    settings = {
      address: ENV["SMTP_ADDRESS"],
      port:    (ENV["SMTP_PORT"].presence || "587").to_i
    }
    settings[:domain] = ENV["SMTP_DOMAIN"] if ENV["SMTP_DOMAIN"].present?

    if ENV["SMTP_USERNAME"].present?
      settings[:user_name]      = ENV["SMTP_USERNAME"]
      settings[:password]       = ENV["SMTP_PASSWORD"]
      settings[:authentication] = (ENV["SMTP_AUTHENTICATION"].presence || "plain").to_sym
    end

    # TLS mode: STARTTLS on 587 (default), implicit TLS on 465, or plain.
    case (ENV["SMTP_TLS"].presence || "starttls").downcase
    when "ssl", "tls"           then settings[:tls] = true
    when "none", "off", "false" then settings[:enable_starttls_auto] = false
    else                             settings[:enable_starttls_auto] = true
    end

    settings
  end

  # HTTPS is opt-in (FORCE_SSL): LAN installs often serve plain HTTP.
  def self.force_ssl_from_env?
    %w[1 true yes].include?(ENV["FORCE_SSL"].to_s.strip.downcase)
  end

  # Absolute links in emails (e.g. password reset) point at APP_HOST. They use
  # APP_PROTOCOL when set (e.g. "https" behind a TLS proxy that doesn't set
  # FORCE_SSL), else https only with FORCE_SSL — plain-HTTP LAN installs would
  # otherwise mail dead https links.
  def self.mailer_url_options_from_env
    protocol = ENV["APP_PROTOCOL"].to_s.strip.downcase.presence_in(%w[http https])
    {
      host: ENV["APP_HOST"].presence || "localhost",
      protocol: protocol || (force_ssl_from_env? ? "https" : "http")
    }
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

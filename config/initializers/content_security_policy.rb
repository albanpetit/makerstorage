# Be sure to restart your server when you modify this file.

# Application-wide content security policy.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Shipped in REPORT-ONLY mode: browsers log violations to the console but block
# nothing. Once a release has run without unexpected violations, set
# `content_security_policy_report_only = false` below to enforce it.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.object_src  :none
    policy.frame_ancestors :none
    policy.form_action :self
    # Inline scripts must carry the request nonce (see the theme script in the
    # application layout); everything else is Vite's same-origin bundles.
    policy.script_src  :self
    # Radix/shadcn set inline style attributes; fonts come from Google Fonts.
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    # Supplier catalog images are hotlinked from their CDNs (any host — Part
    # accepts http and https image URLs, so the policy must too); uploads are
    # served same-origin; previews use blob:/data: URLs.
    policy.img_src     :self, :https, :http, :data, :blob
    # The scanner reads the camera stream into a blob-backed <video>.
    policy.media_src   :self, :blob
    policy.connect_src :self
    # Violations are logged by CspReportsController, so switching to an enforced
    # policy can be judged from real reports first.
    policy.report_uri "/csp-violations"

    if Rails.env.development?
      # Vite dev server: module scripts, HMR websocket, and the React refresh
      # preamble (which needs eval).
      vite = ViteRuby.config.host_with_port
      policy.script_src(*policy.script_src, :unsafe_eval, "http://#{vite}")
      policy.connect_src(*policy.connect_src, "http://#{vite}", "ws://#{vite}")
    end
  end

  # Per-request nonce for the inline scripts we do emit.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end

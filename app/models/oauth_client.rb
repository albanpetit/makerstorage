# An OAuth client registered through Dynamic Client Registration (RFC 7591) by
# an MCP client such as claude.ai or Claude Code before it asks a user for
# access (see Oauth::RegistrationsController). Clients are public: they hold no
# secret and prove possession of each authorization code with PKCE.
class OauthClient < ApplicationRecord
  MAX_REDIRECT_URIS = 10
  MAX_URI_LENGTH = 2000
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1] ::1].freeze

  has_many :oauth_authorizations, dependent: :delete_all

  serialize :redirect_uris, coder: JSON, type: Array

  validates :uid, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 100 }
  validate :redirect_uris_must_be_safe

  before_validation { self.uid ||= SecureRandom.urlsafe_base64(24) }

  # Whether +uri+ is one of the registered redirect URIs. Loopback redirects
  # match whatever their port: native clients (Claude Code) listen on an
  # ephemeral port that changes every run (RFC 8252 §7.3).
  def redirect_uri_allowed?(uri)
    return false if uri.blank?
    return true if redirect_uris.include?(uri)

    requested = self.class.loopback_without_port(uri)
    requested.present? && redirect_uris.any? { |registered| self.class.loopback_without_port(registered) == requested }
  end

  # +uri+ with its port dropped when it is an http loopback URI, else nil.
  def self.loopback_without_port(uri)
    parsed = URI.parse(uri.to_s)
    return nil unless parsed.is_a?(URI::HTTP) && loopback_host?(parsed.host)

    parsed.port = nil
    parsed.to_s
  rescue URI::InvalidURIError
    nil
  end

  def self.loopback_host?(host)
    LOOPBACK_HOSTS.include?(host.to_s.downcase)
  end

  # Only https redirects, or plain http back to the user's own machine: a code
  # sent anywhere else in the clear could be read on the way.
  def self.safe_redirect_uri?(uri)
    return false if uri.to_s.length > MAX_URI_LENGTH

    parsed = URI.parse(uri.to_s)
    return false unless parsed.is_a?(URI::HTTP) && parsed.host.present?
    return false if parsed.fragment || parsed.userinfo

    parsed.scheme == "https" || loopback_host?(parsed.host)
  rescue URI::InvalidURIError
    false
  end

  private

  def redirect_uris_must_be_safe
    uris = Array(redirect_uris)
    if uris.empty?
      errors.add(:redirect_uris, "must list at least one URI")
    elsif uris.size > MAX_REDIRECT_URIS
      errors.add(:redirect_uris, "can list at most #{MAX_REDIRECT_URIS} URIs")
    elsif !uris.all? { |uri| uri.is_a?(String) && self.class.safe_redirect_uri?(uri) }
      errors.add(:redirect_uris, "must be https URIs, or http on localhost")
    end
  end
end

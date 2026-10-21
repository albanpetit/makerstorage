# Access a user granted an OAuth client (an MCP client such as Claude) to one
# organization, read-only. The row first carries a short-lived authorization
# code, then the current access/refresh token pair. Only SHA-256 digests of
# codes and tokens are stored; the plain values are returned once, to the client.
#
# Refresh tokens rotate on every use (OAuth 2.1, public clients), so a leaked
# one stops working as soon as the real client refreshes.
class OauthAuthorization < ApplicationRecord
  SCOPE = "mcp:read"
  CODE_TTL = 10.minutes
  ACCESS_TOKEN_TTL = 1.hour
  REFRESH_TOKEN_TTL = 90.days
  # last_used_at is only rewritten when older than this, so a busy client
  # doesn't write the row on every call.
  LAST_USED_RESOLUTION = 1.minute
  ACCESS_TOKEN_PREFIX = "msat_"
  REFRESH_TOKEN_PREFIX = "msrt_"
  # RFC 7636 §4.1: 43 to 128 unreserved characters.
  CODE_VERIFIER_FORMAT = /\A[A-Za-z0-9\-._~]{43,128}\z/

  class InvalidGrant < StandardError; end

  belongs_to :oauth_client
  belongs_to :user
  belongs_to :organization

  validates :scope, presence: true
  validate :user_must_be_member_of_organization, on: :create

  # Authorizations that reached the token stage (abandoned codes left out).
  scope :connected, -> { where.not(access_token_digest: nil) }

  def self.digest(value)
    ::Digest::SHA256.hexdigest(value.to_s)
  end

  # Records the user's consent and returns the plain authorization code to
  # send back to the client. Also sweeps codes nobody exchanged in time.
  def self.grant!(client:, user:, organization:, redirect_uri:, code_challenge:)
    where(access_token_digest: nil).where(code_expires_at: ...Time.current).delete_all

    code = SecureRandom.urlsafe_base64(32)
    create!(
      oauth_client: client, user: user, organization: organization, scope: SCOPE,
      code_digest: digest(code), code_challenge: code_challenge,
      redirect_uri: redirect_uri, code_expires_at: CODE_TTL.from_now
    )
    code
  end

  # Trades an authorization code (with its PKCE verifier) for a token pair.
  # A code works once: replaying one revokes everything it granted (RFC 6749
  # §4.1.2), since only an attacker would present a used code.
  def self.exchange_code!(client:, code:, redirect_uri:, code_verifier:)
    authorization = find_by(code_digest: digest(code), oauth_client: client) if code.present?
    raise InvalidGrant, "unknown authorization code" if authorization.nil?

    if authorization.access_token_digest.present?
      authorization.destroy
      raise InvalidGrant, "authorization code already used"
    end
    raise InvalidGrant, "authorization code expired" if authorization.code_expires_at.nil? || authorization.code_expires_at.past?
    raise InvalidGrant, "redirect_uri does not match" unless authorization.redirect_uri == redirect_uri
    raise InvalidGrant, "invalid code_verifier" unless authorization.pkce_verified?(code_verifier)

    authorization.issue_tokens!(expected_digest: authorization.access_token_digest)
  end

  # Trades a refresh token for a new token pair, retiring the old one.
  def self.refresh!(client:, refresh_token:)
    authorization = find_by(refresh_token_digest: digest(refresh_token), oauth_client: client) if refresh_token.present?
    raise InvalidGrant, "unknown refresh token" if authorization.nil?
    raise InvalidGrant, "refresh token expired" if authorization.refresh_token_expires_at.past?
    raise InvalidGrant, "access revoked" unless authorization.still_allowed?

    authorization.issue_tokens!(expected_digest: authorization.access_token_digest)
  end

  # The live authorization behind a bearer access token, or nil when the token
  # is unknown or expired, or the user lost access to the organization.
  def self.authenticate(access_token)
    return nil if access_token.blank?

    authorization = includes(:user, :organization).find_by(access_token_digest: digest(access_token))
    return nil if authorization.nil? || authorization.access_token_expires_at.past? || !authorization.still_allowed?

    authorization.touch_last_used
    authorization
  end

  def pkce_verified?(verifier)
    return false if code_challenge.blank? || !verifier.to_s.match?(CODE_VERIFIER_FORMAT)

    expected = Base64.urlsafe_encode64(::Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end

  # The user must still hold an active, accepted membership (a deactivated or
  # removed member loses API access along with UI access) and not be locked out.
  def still_allowed?
    !user.access_locked? && user.member_of_organization?(organization_id)
  end

  # Mints a fresh token pair. The update only applies if nobody rotated the
  # row since it was read (+expected_digest+), so two concurrent exchanges or
  # refreshes of the same grant can't both succeed.
  def issue_tokens!(expected_digest:)
    access_token = ACCESS_TOKEN_PREFIX + SecureRandom.urlsafe_base64(32)
    refresh_token = REFRESH_TOKEN_PREFIX + SecureRandom.urlsafe_base64(32)
    now = Time.current
    attributes = {
      # The code digest stays, so a replayed code is recognized (see .exchange_code!).
      code_challenge: nil, code_expires_at: nil,
      access_token_digest: self.class.digest(access_token), access_token_expires_at: now + ACCESS_TOKEN_TTL,
      refresh_token_digest: self.class.digest(refresh_token), refresh_token_expires_at: now + REFRESH_TOKEN_TTL,
      updated_at: now
    }

    claimed = self.class.where(id: id, access_token_digest: expected_digest).update_all(attributes)
    raise InvalidGrant, "grant already used" unless claimed == 1

    assign_attributes(attributes)
    clear_changes_information
    { access_token: access_token, refresh_token: refresh_token, expires_in: ACCESS_TOKEN_TTL.to_i, scope: scope }
  end

  def touch_last_used
    return if last_used_at && last_used_at > LAST_USED_RESOLUTION.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def user_must_be_member_of_organization
    return if user.nil? || organization.nil? || user.member_of_organization?(organization.id)

    errors.add(:organization, :not_users_organization)
  end
end

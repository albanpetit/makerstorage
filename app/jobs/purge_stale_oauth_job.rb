# Clears OAuth rows nobody can use any more. Dynamic Client Registration is
# open (any visitor can register a client), and an abandoned sign-in leaves an
# authorization code behind, so without this both tables only ever grow.
#
#   authorizations  codes never exchanged in time, and grants whose refresh
#                   token has expired (the client must sign in again anyway)
#   clients         registered more than CLIENT_GRACE_PERIOD ago and holding no
#                   authorization: never used, or every grant revoked/expired
class PurgeStaleOauthJob < ApplicationJob
  queue_as :default

  CLIENT_GRACE_PERIOD = 30.days

  def perform
    now = Time.current
    OauthAuthorization.where(access_token_digest: nil, code_expires_at: ...now).delete_all
    OauthAuthorization.where(refresh_token_expires_at: ...now).delete_all
    OauthClient.where(created_at: ...CLIENT_GRACE_PERIOD.ago)
      .where.not(id: OauthAuthorization.select(:oauth_client_id))
      .delete_all
  end
end

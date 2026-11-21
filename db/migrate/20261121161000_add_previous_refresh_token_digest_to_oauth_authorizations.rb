# The digest of the refresh token a grant last rotated away from, so a reused
# (leaked) one can be recognized and the grant revoked.
class AddPreviousRefreshTokenDigestToOauthAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_authorizations, :previous_refresh_token_digest, :string
    add_index :oauth_authorizations, :previous_refresh_token_digest
  end
end

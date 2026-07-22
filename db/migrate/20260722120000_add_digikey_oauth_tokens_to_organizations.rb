class AddDigikeyOauthTokensToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # DigiKey's Order Status API is user-scoped and needs the 3-legged
    # Authorization Code flow: a connected DigiKey account yields an access token
    # (short-lived) plus a refresh token (rotated on every refresh). Both stored
    # encrypted at rest like the other catalog secrets; `text` for the payload.
    add_column :organizations, :digikey_access_token, :text
    add_column :organizations, :digikey_refresh_token, :text
    add_column :organizations, :digikey_token_expires_at, :datetime
  end
end

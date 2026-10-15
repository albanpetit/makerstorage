class CreateOauthTables < ActiveRecord::Migration[8.1]
  def change
    # MCP clients (Claude, Claude Code…) that registered themselves through
    # OAuth Dynamic Client Registration. Public clients: no secret, PKCE only.
    create_table :oauth_clients do |t|
      t.string :uid, null: false
      t.string :name, null: false
      t.text :redirect_uris, null: false
      t.timestamps
    end
    add_index :oauth_clients, :uid, unique: true

    # One row per access a user granted a client on one organization: the
    # authorization code while the flow is in progress, then the current
    # access/refresh token pair (only their SHA-256 digests are stored).
    create_table :oauth_authorizations do |t|
      t.references :oauth_client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :scope, null: false, default: "mcp:read"

      t.string :code_digest
      t.string :code_challenge
      t.string :redirect_uri
      t.datetime :code_expires_at

      t.string :access_token_digest
      t.datetime :access_token_expires_at
      t.string :refresh_token_digest
      t.datetime :refresh_token_expires_at
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :oauth_authorizations, :code_digest, unique: true
    add_index :oauth_authorizations, :access_token_digest, unique: true
    add_index :oauth_authorizations, :refresh_token_digest, unique: true
  end
end

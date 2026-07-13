class AddDigikeyCredentialsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # DigiKey's Product Information API uses OAuth2 client-credentials, so we
    # store a Client ID + Client Secret pair (both encrypted at rest via Active
    # Record Encryption — see Organization). `text` because the encrypted
    # payload is longer than the raw value.
    add_column :organizations, :digikey_client_id, :text
    add_column :organizations, :digikey_client_secret, :text
  end
end

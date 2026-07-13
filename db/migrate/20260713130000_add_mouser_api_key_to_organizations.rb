class AddMouserApiKeyToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Stored encrypted at rest via Active Record Encryption (see Organization#mouser_api_key).
    # `text` because the encrypted payload is longer than the raw key.
    add_column :organizations, :mouser_api_key, :text
  end
end

class AddMouserOrderApiKeyToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Mouser issues a separate key for the Order/Cart API (distinct from the
    # Search API key). Stored encrypted at rest like the other catalog secrets;
    # `text` because the encrypted payload is longer than the raw key.
    add_column :organizations, :mouser_order_api_key, :text
  end
end

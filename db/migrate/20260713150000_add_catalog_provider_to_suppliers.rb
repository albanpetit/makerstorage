class AddCatalogProviderToSuppliers < ActiveRecord::Migration[8.1]
  # Tags a supplier as the local record for an external catalog integration
  # (Mouser, DigiKey, ...). It links a configured API integration to the
  # supplier used to auto-fill prices on parts, so at most one supplier per
  # organization can represent a given provider.
  def up
    add_column :suppliers, :catalog_provider, :string

    # Backfill existing seeded suppliers by their website domain so orgs created
    # before this column still get their integration link. (SQLite LIKE is
    # case-insensitive for ASCII.)
    execute "UPDATE suppliers SET catalog_provider = 'mouser' WHERE catalog_provider IS NULL AND website LIKE '%mouser.com%'"
    execute "UPDATE suppliers SET catalog_provider = 'digikey' WHERE catalog_provider IS NULL AND website LIKE '%digikey.com%'"

    add_index :suppliers, %i[organization_id catalog_provider],
              unique: true,
              where: "catalog_provider IS NOT NULL",
              name: "index_suppliers_on_organization_id_and_catalog_provider"
  end

  def down
    remove_index :suppliers, name: "index_suppliers_on_organization_id_and_catalog_provider"
    remove_column :suppliers, :catalog_provider
  end
end

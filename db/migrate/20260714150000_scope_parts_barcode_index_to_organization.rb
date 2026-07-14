class ScopePartsBarcodeIndexToOrganization < ActiveRecord::Migration[8.1]
  def change
    remove_index :parts, :barcode, unique: true, where: "barcode IS NOT NULL", name: "index_parts_on_barcode"
    add_index :parts, [ :organization_id, :barcode ], unique: true, where: "barcode IS NOT NULL"
  end
end

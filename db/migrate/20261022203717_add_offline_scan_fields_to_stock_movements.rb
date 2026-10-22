class AddOfflineScanFieldsToStockMovements < ActiveRecord::Migration[8.1]
  def change
    # Movements recorded by the offline scanner: the id the device gave the
    # scan (so a sync retried after a lost response doesn't write it twice) and
    # when it was scanned, which can be long before it reached the server.
    add_column :stock_movements, :offline_uuid, :string
    add_column :stock_movements, :scanned_at, :datetime
    add_index :stock_movements, %i[organization_id offline_uuid], unique: true, where: "offline_uuid IS NOT NULL"
  end
end

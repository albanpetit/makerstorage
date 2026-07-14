class AddIpnToParts < ActiveRecord::Migration[8.1]
  def change
    add_column :parts, :ipn, :string
    add_index :parts, [ :organization_id, :ipn ], unique: true, where: "ipn IS NOT NULL"
  end
end

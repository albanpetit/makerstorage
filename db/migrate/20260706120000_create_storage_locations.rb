class CreateStorageLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :storage_locations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :storage_locations }, null: true

      t.string :name, null: false
      t.string :location_type, null: false
      t.string :code

      t.timestamps
    end

    add_index :storage_locations, [ :organization_id, :name ]
    add_index :storage_locations, :location_type
    add_index :storage_locations, :code
  end
end

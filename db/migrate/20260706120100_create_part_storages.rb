class CreatePartStorages < ActiveRecord::Migration[8.1]
  def change
    create_table :part_storages do |t|
      t.references :part, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      t.integer :quantity, default: 0, null: false

      t.timestamps
    end

    add_index :part_storages, [ :part_id, :storage_location_id ], unique: true, name: "index_part_storages_on_part_and_location"
  end
end

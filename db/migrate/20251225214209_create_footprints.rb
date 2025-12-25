class CreateFootprints < ActiveRecord::Migration[8.1]
  def change
    create_table :footprints do |t|
      t.references :organization, null: false, foreign_key: true

      t.string :name, null: false
      t.text :description
      t.string :mounting_type

      t.timestamps
    end

    add_index :footprints, [ :organization_id, :name ], unique: true
    add_index :footprints, :mounting_type
  end
end

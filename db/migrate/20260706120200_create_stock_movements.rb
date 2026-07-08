class CreateStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_movements do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      t.references :user, foreign_key: true, null: true

      t.string :movement_type, null: false
      t.integer :quantity_delta, null: false
      t.text :reason
      t.string :reference

      t.timestamps
    end

    add_index :stock_movements, :movement_type
    add_index :stock_movements, :created_at
  end
end

class CreateStocktakes < ActiveRecord::Migration[8.1]
  def change
    # A count of one storage zone (and, by default, its sub-zones): its lines
    # snapshot the stock the ledger expects, collect what was actually counted,
    # and completing it writes the differences as adjustment movements.
    create_table :stocktakes do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      t.boolean :include_sub_zones, null: false, default: true
      # Hide the expected quantities while counting.
      t.boolean :blind, null: false, default: false
      t.string :reference
      t.string :status, null: false, default: "in_progress"
      t.text :notes
      t.references :user, foreign_key: true
      t.references :completed_by, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.timestamps
    end
    add_index :stocktakes, %i[organization_id reference], unique: true
    add_index :stocktakes, %i[organization_id status]

    create_table :stocktake_lines do |t|
      t.references :stocktake, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      # What the ledger held when the line was last counted (or when the count
      # started, until then).
      t.integer :expected_quantity, null: false, default: 0
      # Nil until counted.
      t.integer :counted_quantity
      t.datetime :counted_at
      t.references :counted_by, foreign_key: { to_table: :users }
      # The adjustment written when the stocktake was completed, if any.
      t.references :stock_movement, foreign_key: true
      t.timestamps
    end
    add_index :stocktake_lines, %i[stocktake_id part_id storage_location_id], unique: true, name: "index_stocktake_lines_uniqueness"
  end
end

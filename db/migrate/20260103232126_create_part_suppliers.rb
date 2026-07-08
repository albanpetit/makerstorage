class CreatePartSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :part_suppliers do |t|
      t.references :part, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.string :supplier_sku
      t.decimal :unit_price, precision: 10, scale: 2
      t.integer :lead_time_days
      t.string :url
      t.boolean :is_preferred, default: false, null: false
      t.text :notes

      t.timestamps
    end

    # Unique constraint: one supplier SKU per part-supplier combination
    add_index :part_suppliers, [ :part_id, :supplier_id ], unique: true
    add_index :part_suppliers, :supplier_sku
  end
end

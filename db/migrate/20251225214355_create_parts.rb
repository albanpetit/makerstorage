class CreateParts < ActiveRecord::Migration[8.1]
  def change
    create_table :parts do |t|
      # Relations
      t.references :organization, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.references :footprint, null: true, foreign_key: true
      t.references :preferred_supplier, foreign_key: { to_table: :suppliers }, null: true

      # Basic information
      t.string :name, null: false
      t.string :mpn
      t.string :sku
      t.text :description
      t.string :status, default: 'active', null: false

      # Technical specifications
      t.string :value
      t.string :tolerance
      t.string :power_rating
      t.string :voltage_rating
      t.string :package_type
      t.string :manufacturer

      # Compliance & identification
      t.string :barcode
      t.boolean :rohs_compliant, default: false

      # Pricing & inventory
      t.decimal :unit_price, precision: 10, scale: 2
      t.integer :min_stock_threshold, default: 0, null: false
      t.integer :target_stock

      # Supplier information
      t.string :supplier_sku
      t.integer :lead_time_days

      # Notes
      t.text :storage_notes

      t.timestamps
    end

    add_index :parts, [ :organization_id, :mpn ], unique: true, where: "mpn IS NOT NULL"
    add_index :parts, [ :organization_id, :sku ], unique: true, where: "sku IS NOT NULL"
    add_index :parts, :name
    add_index :parts, :manufacturer
    add_index :parts, :value
    add_index :parts, :status
    add_index :parts, :barcode, unique: true, where: "barcode IS NOT NULL"
  end
end

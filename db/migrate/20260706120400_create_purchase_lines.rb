class CreatePurchaseLines < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_lines do |t|
      t.references :purchase, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true

      t.integer :quantity, null: false
      t.decimal :unit_price, precision: 10, scale: 2

      t.timestamps
    end
  end
end

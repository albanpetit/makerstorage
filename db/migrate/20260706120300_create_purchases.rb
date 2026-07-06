class CreatePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :purchases do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true

      t.string :reference
      t.string :status, default: "pending", null: false
      t.date :ordered_at
      t.decimal :total_amount, precision: 10, scale: 2

      t.timestamps
    end

    add_index :purchases, :status
    add_index :purchases, :reference
  end
end

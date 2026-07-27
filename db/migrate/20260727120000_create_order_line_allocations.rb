class CreateOrderLineAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :order_line_allocations do |t|
      t.references :order_line, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      t.integer :quantity, null: false

      t.timestamps
    end
  end
end

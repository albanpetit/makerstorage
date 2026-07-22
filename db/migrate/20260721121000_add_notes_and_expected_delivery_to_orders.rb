class AddNotesAndExpectedDeliveryToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :notes, :text
    add_column :orders, :expected_delivery, :date
  end
end

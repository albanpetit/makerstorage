class AddPriceBreaksToPartSuppliers < ActiveRecord::Migration[8.1]
  def change
    # Quantity price breaks from the supplier, [{ "quantity" => 10, "unit_price" => "0.08" }, …]
    # sorted by quantity. unit_price stays the single-unit (or first break) price.
    add_column :part_suppliers, :price_breaks, :json, null: false, default: []
  end
end

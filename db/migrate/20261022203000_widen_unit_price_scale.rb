class WidenUnitPriceScale < ActiveRecord::Migration[8.1]
  # Unit prices of small parts go below a cent at volume (a 0402 resistor is
  # 0.0021 at 5000+), which two decimals rounded to 0.00. Order totals keep two.
  def up
    change_column :parts, :unit_price, :decimal, precision: 12, scale: 4
    change_column :part_suppliers, :unit_price, :decimal, precision: 12, scale: 4
    change_column :order_lines, :unit_price, :decimal, precision: 12, scale: 4
  end

  def down
    change_column :parts, :unit_price, :decimal, precision: 10, scale: 2
    change_column :part_suppliers, :unit_price, :decimal, precision: 10, scale: 2
    change_column :order_lines, :unit_price, :decimal, precision: 10, scale: 2
  end
end

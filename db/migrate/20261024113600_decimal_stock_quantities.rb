# Quantities in a part's unit can be decimal (2.5 m of wire, 0.5 L of
# alcohol): every stock quantity column becomes decimal(15, 3), read through
# Quantity::Type. Existing whole numbers are kept as they are.
class DecimalStockQuantities < ActiveRecord::Migration[8.1]
  COLUMNS = {
    part_storages: { quantity: { default: 0, null: false } },
    stock_movements: { quantity_delta: { null: false } },
    parts: { min_stock_threshold: { default: 0, null: false }, target_stock: {} },
    order_lines: { quantity: { null: false } },
    order_line_allocations: { quantity: { null: false } },
    project_lines: { quantity: { default: 1, null: false } },
    loan_lines: { quantity: { null: false }, returned_quantity: { default: 0, null: false }, lost_quantity: { default: 0, null: false } },
    stocktake_lines: { expected_quantity: { default: 0, null: false }, counted_quantity: {} }
  }.freeze

  def up
    COLUMNS.each do |table, columns|
      columns.each do |column, options|
        change_column table, column, :decimal, precision: 15, scale: 3, **options
      end
    end
    # How much one pack holds, in the part's unit (a 1 kg spool of filament
    # counted in grams: 1000). Stock can be entered in packs.
    add_column :parts, :pack_size, :decimal, precision: 15, scale: 3
  end

  def down
    remove_column :parts, :pack_size
    COLUMNS.each do |table, columns|
      columns.each do |column, options|
        change_column table, column, :integer, **options
      end
    end
  end
end

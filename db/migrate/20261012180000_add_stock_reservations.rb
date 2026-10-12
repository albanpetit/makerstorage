class AddStockReservations < ActiveRecord::Migration[8.1]
  def change
    # Organization-wide switch: when off, confirmed projects reserve nothing and
    # availability is plain physical stock again.
    add_column :organizations, :stock_reservations_enabled, :boolean, default: true, null: false

    # Set while a confirmed project holds its BOM quantities against other
    # projects; cleared when it is built or released.
    add_column :projects, :reserved_at, :datetime
  end
end

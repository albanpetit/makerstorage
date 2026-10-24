class AddTransferToStockMovements < ActiveRecord::Migration[8.1]
  # Marks the out + in pairs that only move stock between zones (zone moves,
  # bulk moves, bag changes, duplicate merges), so consumption leaves them out
  # without reading the reason text. Rows written before are recognised once
  # here by the reasons those moves have always used.
  REASONS = [ "Moved to %", "Moved from %", "Bulk move to %", "Bulk move from %", "Merged duplicate:%" ].freeze

  def up
    add_column :stock_movements, :transfer, :boolean, default: false, null: false

    conditions = REASONS.map { "reason LIKE #{connection.quote(_1)}" }.join(" OR ")
    execute "UPDATE stock_movements SET transfer = 1 WHERE movement_type IN ('in', 'out') AND (#{conditions})"
  end

  def down
    remove_column :stock_movements, :transfer
  end
end

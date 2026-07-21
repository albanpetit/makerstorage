class RenamePurchasesToOrders < ActiveRecord::Migration[8.1]
  def up
    rename_table :purchases, :orders
    rename_table :purchase_lines, :order_lines
    rename_column :order_lines, :purchase_id, :order_id

    # SQLite recreates indexes on rename_table but drops the partial WHERE clause
    # of the scoped-reference uniqueness index (added in
    # 20260715120000_scope_purchases_reference_index_unique_to_organization), so
    # rebuild it explicitly — otherwise blank/absent references (e.g. draft
    # orders) would collide under a full unique index.
    rebuild_reference_index(unique_scope: true)
  end

  def down
    rebuild_reference_index(unique_scope: false)

    rename_column :order_lines, :order_id, :purchase_id
    rename_table :order_lines, :purchase_lines
    rename_table :orders, :purchases
  end

  private

  def rebuild_reference_index(unique_scope:)
    table = unique_scope ? :orders : :purchases
    name = "index_#{table}_on_organization_id_and_reference"

    remove_index table, name: name if index_name_exists?(table, name)
    add_index table, [ :organization_id, :reference ],
      unique: true, name: name,
      where: "reference IS NOT NULL AND reference != ''"
  end
end

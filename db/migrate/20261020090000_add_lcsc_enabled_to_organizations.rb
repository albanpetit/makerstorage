class AddLcscEnabledToOrganizations < ActiveRecord::Migration[8.1]
  # LCSC has no key to store: its catalog lookup is switched on per organization.
  def change
    add_column :organizations, :lcsc_enabled, :boolean, default: false, null: false
  end
end

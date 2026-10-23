class AddConsumptionSettingsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Suggested low-stock thresholds (PartConsumption): usage is averaged over
    # the last consumption_window_days, and a threshold should hold
    # threshold_cover_days of that usage.
    add_column :organizations, :consumption_window_days, :integer, default: 90, null: false
    add_column :organizations, :threshold_cover_days, :integer, default: 30, null: false
  end
end

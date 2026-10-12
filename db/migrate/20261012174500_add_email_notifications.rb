class AddEmailNotifications < ActiveRecord::Migration[8.1]
  def change
    # Organization-wide switches for the email digest (see NotificationDigestJob).
    add_column :organizations, :notify_low_stock, :boolean, default: true, null: false
    add_column :organizations, :notify_late_orders, :boolean, default: true, null: false
    add_column :organizations, :notification_frequency, :string, default: "daily", null: false
    # Local date of the last digest run, so the hourly job sends at most one per period.
    add_column :organizations, :notifications_sent_on, :date

    # Per-member opt-out, for each organization the user belongs to.
    add_column :organization_memberships, :email_notifications, :boolean, default: true, null: false
  end
end

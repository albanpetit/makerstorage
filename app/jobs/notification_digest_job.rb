# Mails each organization's low-stock / late-order digest (NotificationDigest)
# to its members. Runs hourly (config/recurring.yml) and sends to an
# organization once its local time passes 8am, once per day or per week as set
# in Settings → Notifications. Nothing is sent when the install has no SMTP.
class NotificationDigestJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    return unless NotificationDigest.available?

    Organization.where(notify_low_stock: true).or(Organization.where(notify_late_orders: true)).find_each do |organization|
      next unless organization.notification_digest_due?(now)

      deliver(organization, now)
    end
  end

  private

  def deliver(organization, now)
    date = organization.local_date(now)
    # Claimed before sending: a delivery error mustn't make every later run
    # mail the members who already got it.
    organization.update_columns(notifications_sent_on: date)

    digest = NotificationDigest.new(organization, date: date)
    return if digest.empty?

    organization.notification_recipients.find_each do |user|
      NotificationMailer.digest(user: user, digest: digest).deliver_now
    rescue StandardError => e
      Rails.logger.error("[Notifications] digest for organization #{organization.id} to user #{user.id} failed: #{e.class}: #{e.message}")
    end
  end
end

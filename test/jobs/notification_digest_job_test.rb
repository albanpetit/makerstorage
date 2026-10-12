require "test_helper"

class NotificationDigestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(timezone: "Etc/UTC")
    create_part(organization: @org, min_stock_threshold: 10)
    @now = Time.utc(2026, 10, 12, 9)
  end

  test "mails the digest once per day to each recipient" do
    member = create_user
    @org.organization_memberships.create!(user: member, role: "member")

    assert_emails 2 do
      NotificationDigestJob.perform_now(now: @now)
    end
    assert_equal Date.new(2026, 10, 12), @org.reload.notifications_sent_on

    assert_no_emails do
      NotificationDigestJob.perform_now(now: @now + 1.hour)
    end
  end

  test "sends nothing before 8am local time" do
    assert_no_emails do
      NotificationDigestJob.perform_now(now: @now - 2.hours)
    end
    assert_nil @org.reload.notifications_sent_on
  end

  test "sends nothing when there is nothing to report" do
    @org.parts.destroy_all

    assert_no_emails do
      NotificationDigestJob.perform_now(now: @now)
    end
  end

  test "skips members who opted out and organizations with every alert off" do
    @org.organization_memberships.find_by!(user: @user).update!(email_notifications: false)
    assert_no_emails { NotificationDigestJob.perform_now(now: @now) }

    other_user = create_user
    other = other_user.organizations.first
    other.update!(timezone: "Etc/UTC", notify_low_stock: false, notify_late_orders: false)
    create_part(organization: other, min_stock_threshold: 10)
    assert_no_emails { NotificationDigestJob.perform_now(now: @now + 1.day) }
  end

  test "sends nothing when the install has no SMTP" do
    with_email_notifications(false) do
      assert_no_emails do
        NotificationDigestJob.perform_now(now: @now)
      end
    end
    assert_nil @org.reload.notifications_sent_on
  end

  test "one failed delivery doesn't stop the others" do
    member = create_user
    @org.organization_memberships.create!(user: member, role: "member")
    calls = 0
    # The mailer action is reached through method_missing, so define the
    # singleton method for the test and remove it afterwards.
    NotificationMailer.singleton_class.define_method(:digest) do |**kwargs|
      calls += 1
      raise Net::SMTPFatalError, "550 rejected" if calls == 1

      ActionMailer::MessageDelivery.new(self, :digest, **kwargs)
    end

    assert_emails 1 do
      NotificationDigestJob.perform_now(now: @now)
    end
    assert_equal 2, calls
  ensure
    NotificationMailer.singleton_class.remove_method(:digest) if NotificationMailer.singleton_class.method_defined?(:digest, false)
  end
end

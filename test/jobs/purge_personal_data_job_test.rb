require "test_helper"

class PurgePersonalDataJobTest < ActiveJob::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  def event(created_at)
    ActivityEvent.create!(organization: @org, user: @user, user_name: "Ada", action: ActivityEvent::ACTIONS.first, created_at: created_at)
  end

  def loan(**attrs)
    Loan.new(organization: @org, borrower_name: "Grace", borrower_contact: "grace@example.com", **attrs)
      .tap { |loan| loan.save!(validate: false) }
  end

  test "deletes activity entries past the retention period" do
    old = event(PurgePersonalDataJob::ACTIVITY_RETENTION.ago - 1.day)
    recent = event(1.month.ago)

    PurgePersonalDataJob.perform_now

    assert_not ActivityEvent.exists?(old.id)
    assert ActivityEvent.exists?(recent.id)
  end

  test "clears the borrower contact of loans closed long ago, keeps the loan" do
    old = loan(closed_at: PurgePersonalDataJob::LOAN_CONTACT_RETENTION.ago - 1.day)
    recent = loan(closed_at: 1.week.ago)
    open = loan(closed_at: nil, created_at: 3.years.ago)

    PurgePersonalDataJob.perform_now

    assert_nil old.reload.borrower_contact
    assert_equal "Grace", old.borrower_name
    assert_equal "grace@example.com", recent.reload.borrower_contact
    assert_equal "grace@example.com", open.reload.borrower_contact
  end
end

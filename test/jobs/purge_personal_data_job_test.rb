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
    assert Loan.exists?(old.id)
    assert_equal "grace@example.com", recent.reload.borrower_contact
    assert_equal "grace@example.com", open.reload.borrower_contact
  end

  test "renames a borrower without an account a year after the loan closed, in its movements and log too" do
    part = create_part(organization: @org)
    zone = create_storage_location(organization: @org)
    StockMovement.create!(organization: @org, part: part, storage_location: zone, movement_type: "in", quantity_delta: 5)
    old = loan(closed_at: PurgePersonalDataJob::LOAN_CONTACT_RETENTION.ago - 1.day, reference: "LN-20240101-1")
    out = StockMovement.create!(organization: @org, part: part, storage_location: zone, movement_type: "out", quantity_delta: -1,
                                reason: "Lent to Grace", reference: old.reference)
    back = StockMovement.create!(organization: @org, part: part, storage_location: zone, movement_type: "in", quantity_delta: 1,
                                 reason: "Returned by Grace", reference: old.reference)
    entry = ActivityEvent.create!(organization: @org, user: @user, user_name: "Ada", action: "update", subject_type: "Loan",
                                  subject_id: old.id, subject_label: "LN-20240101-1 · Grace", details: { "borrower_name" => [ "Grace", "Grace H." ] })
    member = loan(closed_at: 2.years.ago, borrower: @user, borrower_name: "Test User")
    recent = loan(closed_at: 1.week.ago)

    PurgePersonalDataJob.perform_now

    assert_equal Loan::FORMER_BORROWER_NAME, old.reload.borrower_name
    assert_equal "Lent to Former borrower", out.reload.reason
    assert_equal "Returned by Former borrower", back.reload.reason
    assert_equal "LN-20240101-1 · Former borrower", entry.reload.subject_label
    assert_equal [ "Former borrower", "Grace H." ], entry.details["borrower_name"]
    assert_equal "Test User", member.reload.borrower_name
    assert_equal "Grace", recent.reload.borrower_name
  end
end

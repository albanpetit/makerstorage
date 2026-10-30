# Enforces the retention periods the privacy policy promises (GDPR storage
# limitation), so personal data doesn't outlive its use:
#
#   activity log    entries older than ACTIVITY_RETENTION (they name who did what)
#   loan contacts   the borrower's email/phone on loans closed more than
#                   LOAN_CONTACT_RETENTION ago; the loan and the name stay as
#                   stock history
class PurgePersonalDataJob < ApplicationJob
  queue_as :default

  ACTIVITY_RETENTION = 2.years
  LOAN_CONTACT_RETENTION = 1.year

  def perform
    ActivityEvent.where(created_at: ...ACTIVITY_RETENTION.ago).in_batches(of: 1000).delete_all
    Loan.where(closed_at: ...LOAN_CONTACT_RETENTION.ago).where.not(borrower_contact: [ nil, "" ])
      .update_all(borrower_contact: nil)
  end
end

# Enforces the retention periods the privacy policy promises (GDPR storage
# limitation), so personal data doesn't outlive its use:
#
#   activity log    entries older than ACTIVITY_RETENTION (they name who did what)
#   loan contacts   the borrower's email/phone on loans closed more than
#                   LOAN_CONTACT_RETENTION ago; the loan stays as stock
#                   history, and so does the name of a borrower who has an
#                   account (renamed when it's deleted). A borrower without
#                   one becomes Loan::FORMER_BORROWER_NAME, in the loan's
#                   movements and activity entries too
class PurgePersonalDataJob < ApplicationJob
  queue_as :default

  ACTIVITY_RETENTION = 2.years
  LOAN_CONTACT_RETENTION = 1.year

  def perform
    ActivityEvent.where(created_at: ...ACTIVITY_RETENTION.ago).in_batches(of: 1000).delete_all
    Loan.where(closed_at: ...LOAN_CONTACT_RETENTION.ago).where.not(borrower_contact: [ nil, "" ])
      .update_all(borrower_contact: nil)
    # Someone without an account: their name goes too (members keep theirs on
    # the loans while their account exists; deleting it renames them).
    Loan.anonymize_borrower(
      Loan.where(closed_at: ...LOAN_CONTACT_RETENTION.ago, borrower_id: nil).where.not(borrower_name: [ Loan::FORMER_BORROWER_NAME, User::DELETED_USER_NAME ]),
      Loan::FORMER_BORROWER_NAME
    )
  end
end

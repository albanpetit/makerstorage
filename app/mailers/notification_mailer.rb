# Low-stock, late-order and overdue-loan digest, sent by NotificationDigestJob to each member
# who hasn't opted out (Profile → Email notifications).
class NotificationMailer < ApplicationMailer
  def digest(user:, digest:)
    @user = user
    @digest = digest
    @organization = digest.organization

    # Each member gets the digest in the language they picked (English when
    # they follow their browser's, which a background job can't know).
    I18n.with_locale(user.locale || I18n.default_locale) do
      counts = []
      counts << t("mail.digest.subject_low_stock", count: digest.low_stock.size) if digest.low_stock.any?
      counts << t("mail.digest.subject_late_orders", count: digest.late_orders.size) if digest.late_orders.any?
      counts << t("mail.digest.subject_overdue_loans", count: digest.overdue_loans.size) if digest.overdue_loans.any?

      mail to: user.email, subject: t("mail.digest.subject", organization: @organization.name, counts: counts.to_sentence)
    end
  end
end

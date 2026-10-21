# Low-stock, late-order and overdue-loan digest, sent by NotificationDigestJob to each member
# who hasn't opted out (Profile → Email notifications).
class NotificationMailer < ApplicationMailer
  def digest(user:, digest:)
    @user = user
    @digest = digest
    @organization = digest.organization

    counts = []
    counts << "#{digest.low_stock.size} low-stock #{'part'.pluralize(digest.low_stock.size)}" if digest.low_stock.any?
    counts << "#{digest.late_orders.size} late #{'order'.pluralize(digest.late_orders.size)}" if digest.late_orders.any?
    counts << "#{digest.overdue_loans.size} overdue #{'loan'.pluralize(digest.overdue_loans.size)}" if digest.overdue_loans.any?

    mail to: user.email, subject: "#{@organization.name}: #{counts.to_sentence}"
  end
end

# Loan updates used to log the borrower's email/phone in clear in the activity
# log, which outlives the contact (cleared a year after the loan closes). Keep
# that a contact changed, not its values, as Loan now logs it.
class HideBorrowerContactsInActivityLog < ActiveRecord::Migration[8.1]
  class Event < ActiveRecord::Base
    self.table_name = "activity_events"
  end

  def up
    Event.where(subject_type: "Loan").where("details LIKE ?", "%borrower_contact%").find_each do |event|
      details = event.details.to_h
      next unless details.key?("borrower_contact")

      event.update_columns(details: details.merge("borrower_contact" => nil))
    end
  end

  def down
    # The values are gone.
  end
end

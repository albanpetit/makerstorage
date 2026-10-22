require "active_support/concern"

# Shared by the CSV exports (movements ledger, stocktake reports).
module CsvText
  extend ActiveSupport::Concern

  private

  # User-entered text starting with = + - @ (or a tab/CR) is run as a formula
  # when the export is opened in a spreadsheet; a leading quote neutralizes it.
  def csv_text(value)
    value.to_s.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
  end
end

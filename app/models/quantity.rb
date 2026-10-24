# Stock quantities in a part's unit: whole numbers for count units (pieces,
# rolls, lots), up to three decimals for measure units ("2.5" m of wire, "340"
# g of filament, "0.5" L of isopropyl alcohol). See Part::DECIMAL_UNITS.
#
# Quantity columns are decimal(15, 3); models read them through Quantity::Type,
# which hands back an Integer when the value is whole and a Float otherwise, so
# piece counts keep printing as "12" (not "12.0") in flash messages, JSON
# props and CSV exports, and JSON numbers stay numbers (a BigDecimal would be
# serialized as a string).
module Quantity
  SCALE = 3
  MAX = ApplicationRecord::MAX_INTEGER

  # The number typed in +value+ ("2.5", "2,5", " 3 ", 4, 1.25), normalized, or
  # nil when it isn't one. A French decimal comma is accepted.
  def self.parse(value)
    case value
    when nil then nil
    when Numeric then normalize(value)
    else
      text = value.to_s.strip.tr(",", ".")
      normalize(BigDecimal(text)) if text.match?(/\A[-+]?(\d+(\.\d*)?|\.\d+)\z/)
    end
  end

  # +number+ rounded to SCALE decimals: an Integer when whole, else a Float.
  def self.normalize(number)
    return nil if number.nil?

    rounded = BigDecimal(number.to_s).round(SCALE)
    rounded.frac.zero? ? rounded.to_i : rounded.to_f
  end

  # The exact sum of +values+ (nil counts as 0), normalized: adding Floats
  # would give 0.30000000000000004 for 0.1 + 0.2.
  def self.sum(*values)
    normalize(values.flatten.sum(BigDecimal(0)) { |value| BigDecimal((value || 0).to_s) })
  end

  def self.whole?(number)
    number.nil? || BigDecimal(number.to_s).frac.zero?
  end

  # +number+ for a message, in the current locale ("2.5" or "2,5") with the
  # unit's symbol when it is a measure ("2,5 m").
  def self.format(number, unit = nil)
    text = ActiveSupport::NumberHelper.number_to_delimited(normalize(number || 0), separator: I18n.t("number.format.separator", default: "."), delimiter: "")
    symbol = Part::UNIT_SYMBOLS[unit.to_s]
    symbol ? "#{text} #{symbol}" : text
  end

  # Reads decimal columns as Integer (whole) or Float values, see above.
  class Type < ActiveModel::Type::Decimal
    def initialize(**)
      super(precision: 15, scale: SCALE)
    end

    def serialize(value)
      value.nil? ? nil : BigDecimal(value.to_s)
    end

    private

    def cast_value(value)
      value.is_a?(String) ? Quantity.parse(value) : Quantity.normalize(super)
    end
  end
end

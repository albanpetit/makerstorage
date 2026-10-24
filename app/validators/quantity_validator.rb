# Validates a Quantity attribute (see Quantity):
#
#   validates :quantity, quantity: { greater_than: 0, unit_of: :part }
#
# Options: greater_than / greater_than_or_equal_to (bounds), other_than,
# allow_nil, and unit_of, the method returning the part whose unit applies:
# a count unit (pieces, rolls, lots) only takes whole numbers. Every value is
# capped at Quantity::MAX either way.
class QuantityValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    if value.nil?
      raw = record.read_attribute_before_type_cast(attribute) if record.respond_to?(:read_attribute_before_type_cast)
      record.errors.add(attribute, raw.blank? ? :blank : :not_a_number) unless options[:allow_nil] && raw.blank?
      return
    end

    if options.key?(:greater_than) && value <= options[:greater_than]
      record.errors.add(attribute, :greater_than, count: options[:greater_than])
    elsif options.key?(:greater_than_or_equal_to) && value < options[:greater_than_or_equal_to]
      record.errors.add(attribute, :greater_than_or_equal_to, count: options[:greater_than_or_equal_to])
    elsif options.key?(:other_than) && value == options[:other_than]
      record.errors.add(attribute, :other_than, count: options[:other_than])
    elsif value.abs > Quantity::MAX
      record.errors.add(attribute, :less_than_or_equal_to, count: Quantity::MAX)
    elsif !Quantity.whole?(value) && (part = unit_part(record)) && !part.decimal_quantities?
      record.errors.add(attribute, :whole_quantity_for_unit, unit: part.unit_label)
    end
  end

  private

  def unit_part(record)
    case options[:unit_of]
    when nil then nil
    when :itself then record
    else record.public_send(options[:unit_of])
    end
  end
end

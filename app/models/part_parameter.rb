# One part's value for a parameter: the text as typed ("4k7") and, for number
# parameters, its value in the parameter's unit (4700.0), which the inventory
# filters and compares on.
class PartParameter < ApplicationRecord
  belongs_to :part
  belongs_to :parameter_definition

  validates :value, presence: true, length: { maximum: 100 }
  validates :parameter_definition_id, uniqueness: { scope: :part_id }
  validate :definition_must_belong_to_same_organization
  validate :value_must_fit_definition

  # Before save rather than before validation: parts save their parameters
  # without validating them again (autosave).
  before_save :compute_numeric_value

  def name
    parameter_definition.name
  end

  def display_value
    parameter_definition.display(value, numeric_value)
  end

  private

  def compute_numeric_value
    self.value = value.to_s.strip
    self.numeric_value = parameter_definition.parse(value)
  end

  def definition_must_belong_to_same_organization
    return if parameter_definition.nil? || part.nil?

    errors.add(:parameter_definition, "must belong to the same organization as the part") if parameter_definition.organization_id != part.organization_id
  end

  def value_must_fit_definition
    return if value.blank? || parameter_definition.nil? || !parameter_definition.number?
    return if parameter_definition.parse(value)

    unit = parameter_definition.unit
    errors.add(:value, "“#{value.strip}” is not #{unit ? "a value in #{unit}" : 'a number'}")
  end
end

# A technical parameter an organization records on its parts: "Resistance" in
# Ω, "Tolerance" in %, "Dielectric" as text. Number parameters store each
# part's value in the unit itself (ParameterValue), so the inventory can filter
# them by range ("10k to 47k") whatever way they were typed. Categories list
# the parameters their parts usually have (CategoryParameter), which the part
# form proposes.
class ParameterDefinition < ApplicationRecord
  VALUE_TYPES = %w[number text].freeze

  # The set "Add standard parameters" installs. +categories+ matches the
  # category names whose template gets the parameter (English and French);
  # +field+ is the part column it mirrors (see Part#sync_parameter_fields).
  STANDARD = [
    { name: "Resistance", unit: "Ω", categories: /r[ée]sist/i },
    { name: "Capacitance", unit: "F", categories: /capacit|condensat/i },
    { name: "Inductance", unit: "H", categories: /induct|bobine/i },
    { name: "Tolerance", unit: "%", categories: /r[ée]sist|capacit|condensat|induct|bobine/i, field: :tolerance },
    { name: "Voltage rating", unit: "V", categories: /capacit|condensat/i, field: :voltage_rating },
    { name: "Power rating", unit: "W", categories: /r[ée]sist/i, field: :power_rating },
    { name: "Current rating", unit: "A", categories: /induct|bobine/i },
    { name: "Frequency", unit: "Hz", categories: /crystal|quartz|oscillat/i },
    { name: "Dielectric", value_type: "text", categories: /capacit|condensat/i },
    { name: "Color", value_type: "text", categories: /\bleds?\b/i }
  ].freeze

  # Part columns kept in step with a parameter of the same name.
  FIELD_PARAMETERS = STANDARD.select { |standard| standard[:field] }.to_h { |standard| [ standard[:field], standard[:name] ] }.freeze

  # Units whose number parameter the part's free-text "Value" fills in, when
  # it is in the part's category template (a resistor's "4k7").
  VALUE_UNITS = %w[Ω F H].freeze

  belongs_to :organization
  has_many :part_parameters, dependent: :destroy
  has_many :category_parameters, dependent: :destroy
  has_many :categories, through: :category_parameters

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :value_type, inclusion: { in: VALUE_TYPES }
  validates :unit, length: { maximum: 12 }
  validates :description, length: { maximum: 500 }
  validate :values_must_fit, on: :update, if: -> { will_save_change_to_value_type? || will_save_change_to_unit? }

  after_update :recompute_values, if: -> { saved_change_to_value_type? || saved_change_to_unit? }

  scope :alphabetical, -> { order(Arel.sql("LOWER(parameter_definitions.name)")) }

  def number?
    value_type == "number"
  end

  # +text+ in this parameter's unit (a Float), nil when it isn't a number in
  # it. Text parameters have no numeric value.
  def parse(text)
    ParameterValue.parse(text, unit) if number?
  end

  # How a value reads in lists: number values in a canonical form ("4.7 kΩ"),
  # text values as typed.
  def display(value, numeric_value)
    number? && numeric_value ? ParameterValue.format(numeric_value, unit) : value
  end

  # Adds the STANDARD parameters the organization doesn't have yet (by name),
  # gives the categories named for them their template, then fills the parts'
  # parameters from their Value, Tolerance, Voltage and Power fields.
  # Returns counts for the flash message.
  def self.install_standard!(organization)
    transaction do
      existing = organization.parameter_definitions.index_by { |definition| definition.name.downcase }
      added = 0
      definitions = STANDARD.to_h do |standard|
        definition = existing[standard[:name].downcase] || begin
          added += 1
          organization.parameter_definitions.create!(name: standard[:name], unit: standard[:unit],
                                                     value_type: standard.fetch(:value_type, "number"))
        end
        [ standard, definition ]
      end

      linked = organization.categories.order(:id).count do |category|
        matches = definitions.select { |standard, _| category.name.match?(standard[:categories]) }.values
        next false if matches.empty?

        position = category.category_parameters.maximum(:position).to_i
        new_links = matches.reject { |definition| category.category_parameters.exists?(parameter_definition: definition) }
        new_links.each { |definition| category.category_parameters.create!(parameter_definition: definition, position: position += 1) }
        new_links.any?
      end

      filled = organization.parts.includes(:part_parameters).find_each.sum { |part| part.fill_parameters_from_fields! }
      { added: added, categories: linked, parameters: filled }
    end
  end

  private

  def normalize
    self.name = name.to_s.squish
    self.unit = number? ? unit.to_s.strip.presence : nil
  end

  # A number parameter's values must all read as numbers in its (new) unit.
  def values_must_fit
    return unless number?

    misfits = part_parameters.reject { |parameter| ParameterValue.parse(parameter.value, unit) }
    return if misfits.empty?

    examples = misfits.first(3).map { |parameter| "“#{parameter.value}”" }.to_sentence
    errors.add(:base, unit ? :values_not_in_unit : :values_not_numbers, count: misfits.size, name: name, unit: unit, examples: examples)
  end

  def recompute_values
    part_parameters.find_each do |parameter|
      parameter.update_column(:numeric_value, parse(parameter.value))
    end
  end
end

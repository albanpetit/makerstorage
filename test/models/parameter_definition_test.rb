require "test_helper"

class ParameterDefinitionTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
  end

  test "names are unique per organization regardless of case" do
    @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")

    duplicate = @org.parameter_definitions.build(name: "resistance")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
    assert create_organization.parameter_definitions.build(name: "Resistance").valid?
  end

  test "text parameters have no unit" do
    definition = @org.parameter_definitions.create!(name: "Dielectric", value_type: "text", unit: "F")

    assert_nil definition.unit
    assert_nil definition.parse("X7R")
    assert_equal "X7R", definition.display("X7R", nil)
  end

  test "rejects an unknown value type" do
    assert_not @org.parameter_definitions.build(name: "Gain", value_type: "date").valid?
  end

  test "changing the type or unit recomputes the values, and is refused when some no longer read" do
    definition = @org.parameter_definitions.create!(name: "Value", value_type: "text")
    part = create_part(organization: @org)
    parameter = part.part_parameters.create!(parameter_definition: definition, value: "47k")
    assert_nil parameter.numeric_value

    definition.update!(value_type: "number", unit: "Ω")
    assert_equal 47_000.0, parameter.reload.numeric_value

    part.part_parameters.create!(parameter_definition: @org.parameter_definitions.create!(name: "Label", value_type: "text"), value: "blue")
    label = @org.parameter_definitions.find_by!(name: "Label")
    assert_not label.update(value_type: "number")
    assert_match(/1 value of Label is not a number \(“blue”\)/, label.errors.full_messages.to_sentence)
  end

  test "deleting a parameter deletes its values and template links" do
    definition = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    category = create_category(organization: @org)
    category.category_parameters.create!(parameter_definition: definition)
    part = create_part(organization: @org, category: category)
    part.part_parameters.create!(parameter_definition: definition, value: "10k")

    definition.destroy!

    assert_empty part.part_parameters.reload
    assert_empty category.category_parameters.reload
  end

  test "install_standard! adds the set once, templates matching categories and fills parts from their fields" do
    passives = create_category(organization: @org, name: "Passives")
    resistors = create_category(organization: @org, name: "Résistances", parent: passives)
    create_category(organization: @org, name: "Condensateurs")
    @org.parameter_definitions.create!(name: "tolerance", unit: "%")
    part = create_part(organization: @org, category: resistors, value: "4k7", tolerance: "1%", power_rating: "1/4W", voltage_rating: "lots")

    result = ParameterDefinition.install_standard!(@org)

    assert_equal ParameterDefinition::STANDARD.size - 1, result[:added]
    assert_equal 2, result[:categories]
    assert_equal 2, result[:parameters], "the tolerance was already filled in when the part was saved"
    assert_equal %w[Resistance tolerance Power\ rating], resistors.parameter_definitions.map(&:name)
    values = part.reload.part_parameters.includes(:parameter_definition).to_h { |p| [ p.name, p.display_value ] }
    assert_equal({ "Resistance" => "4.7 kΩ", "tolerance" => "1%", "Power rating" => "250 mW" }, values)

    again = ParameterDefinition.install_standard!(@org)
    assert_equal({ added: 0, categories: 0, parameters: 0 }, again)
  end
end

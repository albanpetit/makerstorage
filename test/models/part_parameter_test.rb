require "test_helper"

class PartParameterTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    @tolerance = @org.parameter_definitions.create!(name: "Tolerance", unit: "%")
    @power = @org.parameter_definitions.create!(name: "Power rating", unit: "W")
    @dielectric = @org.parameter_definitions.create!(name: "Dielectric", value_type: "text")
    @resistors = create_category(organization: @org, name: "Resistors")
    @resistors.update!(parameter_template: [ @resistance.id, @tolerance.id ])
  end

  def values(part)
    part.reload.part_parameters.includes(:parameter_definition).to_h { |p| [ p.name, p.value ] }
  end

  test "stores number values in the unit and text values as typed" do
    part = create_part(organization: @org)
    resistance = part.part_parameters.create!(parameter_definition: @resistance, value: " 4k7 ")
    dielectric = part.part_parameters.create!(parameter_definition: @dielectric, value: "X7R")

    assert_equal [ "4k7", 4700.0, "4.7 kΩ" ], [ resistance.value, resistance.numeric_value, resistance.display_value ]
    assert_equal [ "X7R", nil, "X7R" ], [ dielectric.value, dielectric.numeric_value, dielectric.display_value ]
  end

  test "a number parameter refuses a value that isn't a number in its unit" do
    parameter = create_part(organization: @org).part_parameters.build(parameter_definition: @resistance, value: "big")

    assert_not parameter.valid?
    assert_includes parameter.errors[:value], "“big” is not a value in Ω"
  end

  test "a part only takes its own organization's parameters, once each" do
    part = create_part(organization: @org)
    foreign = create_organization.parameter_definitions.create!(name: "Resistance", unit: "Ω")

    assert_not part.part_parameters.build(parameter_definition: foreign, value: "1k").valid?
    part.part_parameters.create!(parameter_definition: @resistance, value: "1k")
    assert_not part.part_parameters.build(parameter_definition: @resistance, value: "2k").valid?
  end

  test "parameter_values= adds, changes and removes values, saved with the part" do
    part = create_part(organization: @org)
    part.update!(parameter_values: { @resistance.id.to_s => "10k", @dielectric.id.to_s => "C0G" })
    assert_equal({ "Resistance" => "10k", "Dielectric" => "C0G" }, values(part))

    part.update!(parameter_values: { @resistance.id.to_s => "22k", @dielectric.id.to_s => "" })
    assert_equal({ "Resistance" => "22k" }, values(part))
  end

  test "parameter_values= with another organization's parameter doesn't save" do
    foreign = create_organization.parameter_definitions.create!(name: "Gain", unit: "dB")
    part = create_part(organization: @org)

    assert_not part.update(parameter_values: { foreign.id => "20" })
    assert_empty part.part_parameters.reload
  end

  test "an invalid value keeps the part from saving, with the error on :parameters" do
    part = create_part(organization: @org, name: "Kept")
    part.assign_attributes(name: "Changed", parameter_values: { @resistance.id => "big" })

    assert_not part.save
    assert_equal [ "Resistance: “big” is not a value in Ω" ], part.errors[:parameters]
    assert_equal "Kept", part.reload.name
  end

  test "the Value fills in the template's first Ω, F or H parameter it reads as" do
    part = create_part(organization: @org, category: @resistors, value: "4k7")
    assert_equal({ "Resistance" => "4k7" }, values(part))

    part.update!(value: "10k")
    assert_equal({ "Resistance" => "10k" }, values(part))

    part.update!(value: "DNP")
    assert_equal({ "Resistance" => "10k" }, values(part), "a Value that isn't a resistance leaves it alone")

    other = create_part(organization: @org, value: "4k7")
    assert_empty other.part_parameters, "no template, no guess"
  end

  test "the Tolerance, Voltage and Power fields and their parameters stay in step" do
    part = create_part(organization: @org, tolerance: "5%", power_rating: "1/4W")
    assert_equal({ "Tolerance" => "5%", "Power rating" => "1/4W" }, values(part))

    part.update!(tolerance: "1%")
    assert_equal "1%", values(part)["Tolerance"]

    part.update!(parameter_values: { @tolerance.id => "2" })
    assert_equal "2%", part.reload.tolerance, "a bare number gets its unit"

    part.update!(parameter_values: { @power.id => "" })
    assert_nil part.reload.power_rating

    part.update!(tolerance: "")
    assert_not values(part).key?("Tolerance")
  end

  test "a parameter changed in the same save wins over its field" do
    part = create_part(organization: @org, tolerance: "5%")
    part.update!(tolerance: "10%", parameter_values: { @tolerance.id => "1%" })

    assert_equal "1%", part.reload.tolerance
    assert_equal "1%", values(part)["Tolerance"]
  end

  test "a field value that isn't a number in the unit is left out" do
    part = create_part(organization: @org, power_rating: "high")
    assert_empty part.part_parameters
    assert_equal "high", part.power_rating
  end

  test "deleting the part deletes its parameters" do
    part = create_part(organization: @org)
    part.part_parameters.create!(parameter_definition: @resistance, value: "1k")

    assert_difference -> { PartParameter.count }, -1 do
      part.destroy!
    end
  end
end

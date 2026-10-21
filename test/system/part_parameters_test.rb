require "application_system_test_case"

class PartParametersTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @resistors = create_category(organization: @org, name: "Resistors")
    ParameterDefinition.install_standard!(@org)
    @r1k = create_part(organization: @org, category: @resistors, name: "Resistor 1k", value: "1k")
    @r22k = create_part(organization: @org, category: @resistors, name: "Resistor 22k", value: "22k")
    @r100k = create_part(organization: @org, category: @resistors, name: "Resistor 100k", value: "100k")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "the part form proposes the category's parameters and saves them" do
    visit parts_path(new: 1)
    find("input[placeholder='e.g. Resistor 10k 1% 0603']").fill_in(with: "Resistor 4k7 1%")
    find("#part-category").click
    find("[role='option']", text: "Resistors").click

    fill_in "Resistance", with: "4k7"
    fill_in "Tolerance", with: "1%"
    click_on "Add part"

    assert_no_selector "[role='dialog']", wait: 10
    part = @org.parts.find_by!(name: "Resistor 4k7 1%")
    assert_equal 4700.0, part.part_parameters.joins(:parameter_definition).find_by!(parameter_definitions: { name: "Resistance" }).numeric_value
    assert_equal "1%", part.tolerance
  end

  test "the inventory filters a category on a parameter range and shows its columns" do
    visit parts_path(category: @resistors.id)
    assert_selector "th", text: "Resistance"
    assert_selector "td", text: "22 kΩ"

    click_on "Resistance"
    within("[role='dialog']") do
      fill_in "Min", with: "10k"
      fill_in "Max", with: "47k"
      click_on "Apply"
    end

    assert_text "Resistance: 10 kΩ – 47 kΩ"
    assert_text "Resistor 22k"
    assert_no_text "Resistor 1k"
    assert_no_text "Resistor 100k"
  end
end

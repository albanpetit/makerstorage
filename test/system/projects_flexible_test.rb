require "application_system_test_case"

# Projects without a BOM file: start empty, add lines by hand, build several
# kits at once, then branch a new revision.
class ProjectsFlexibleTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    location = create_storage_location(organization: @org, name: "Drawer 1")
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RC0603-10K")
    StockMovement.create!(organization: @org, part: @resistor, storage_location: location, movement_type: "in", quantity_delta: 50)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "building a project by hand and branching a revision" do
    visit projects_path
    click_on "New project"
    within("[role='dialog']") do
      fill_in "Project name", with: "Weather station"
      click_on "Create empty project"
    end
    assert_text "Project created. Add its parts below."
    assert_text "No lines yet."

    click_on "Add line"
    within("[role='dialog']") { find("#line-part").click }
    find("[role='option']", text: "Resistor 10k").click
    within("[role='dialog']") do
      fill_in "Designators", with: "R1, R2"
      fill_in "Quantity", with: "2"
      click_on "Add line"
    end
    assert_text "Line added."
    assert_text "R1, R2"

    click_on "Build"
    within("[role='alertdialog']") do
      fill_in "Kits", with: "3"
      fill_in "Note", with: "Open day"
      click_on "Deduct stock"
    end
    assert_text "(3 kits)"
    within(:xpath, "//div[h2[text()='Build history']]/following-sibling::*[1]") do
      assert_text "Open day"
      assert_text "6 (1 ref)"
    end
    assert_equal 44, @resistor.reload.total_quantity

    click_on "New revision"
    within("[role='dialog']") do
      assert_field "Revision", with: "B"
      click_on "Create revision"
    end
    assert_text "Revision B created"
    assert_text "rev B"
    assert_text "R1, R2"
    assert_no_text "Build history"
    assert_equal 2, @org.projects.where(name: "Weather station").count
  end
end

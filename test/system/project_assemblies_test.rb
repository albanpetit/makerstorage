require "application_system_test_case"

# A project using another one as a sub-assembly: built along, then stocked
# through a built item.
class ProjectAssembliesSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @drawer = create_storage_location(organization: @org, name: "Drawer 1")
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RC0603-10K")
    @case = create_part(organization: @org, name: "Robot case")
    @built = create_part(organization: @org, name: "Driver board (assembled)")
    stock(@resistor, 50)
    stock(@case, 5)

    @board = create_project(organization: @org, name: "Driver board", revision: "B", reference: "PRJ-20261023-1")
    @board.project_lines.create!(part: @resistor, quantity: 4, match_type: "manual", designators: "R1-R4")
    @robot = create_project(organization: @org, name: "Robot", reference: "PRJ-20261023-2")
    @robot.project_lines.create!(part: @case, quantity: 1, match_type: "manual")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "using a project as a sub-assembly, then stocking it as a built item" do
    visit project_path(@robot)
    click_on "Add line"
    within("[role='dialog']") do
      click_on "Sub-assembly"
      find("#line-subproject").click
    end
    find("[role='option']", text: "Driver board · rev B").click
    within("[role='dialog']") do
      fill_in "Quantity", with: "2"
      click_on "Add line"
    end
    assert_text "Line added."
    assert_text "Built along: 1 part"
    assert_text "Parts from sub-assemblies"

    click_on "Build"
    within("[role='alertdialog']") { click_on "Deduct stock" }
    assert_text "Stock deducted"
    assert_equal 42, @resistor.reload.total_quantity

    # The board gets a built item: the robot now takes assembled boards from stock.
    visit project_path(@board)
    assert_text "Used in"
    click_on "Edit", match: :first
    within("[role='dialog']") { find("#edit-project-output-part").click }
    find("[role='option']", text: "Driver board (assembled)").click
    within("[role='dialog']") { click_on "Save" }
    assert_text "Project updated."

    click_on "Build"
    within("[role='alertdialog']") do
      fill_in "Kits", with: "2"
      find("#build-zone").click
    end
    find("[role='option']", text: "Drawer 1").click
    within("[role='alertdialog']") { click_on "Deduct stock" }
    assert_text "2 × Driver board (assembled) added to stock."
    assert_equal 2, @built.reload.total_quantity

    visit project_path(@robot)
    assert_text "Stocked as Driver board (assembled)"
  end

  private

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @drawer, movement_type: "in", quantity_delta: quantity)
  end
end

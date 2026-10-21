require "application_system_test_case"

class StocktakeSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @cabinet = create_storage_location(organization: @org, name: "Cabinet A", location_type: "cabinet", code: "CA")
    @drawer = create_storage_location(organization: @org, name: "Drawer 1", location_type: "drawer", code: "CA-1", parent: @cabinet)
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RC0603-10K", ipn: "R-10K")
    @cap = create_part(organization: @org, name: "Cap 100nF", mpn: "CL10B104", ipn: "C-100N")
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "in", quantity_delta: 50)
    StockMovement.create!(organization: @org, part: @cap, storage_location: @drawer, movement_type: "in", quantity_delta: 20)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "count a zone with the scanner field and complete the stocktake" do
    visit stocktakes_path
    assert_selector "h1", text: "Stocktakes", wait: 10
    assert_text "Zones due for a count"

    # Start from the due zone's Count button: the zone comes preselected.
    within("tr", text: "Cabinet A > Drawer 1") { click_on "Count" }
    within("[role='dialog']") { click_on "Start counting" }
    assert_text "2 lines to count", wait: 10

    # A scanned label opens the part's line; typing the count and Enter saves it.
    find("input[aria-label='Scan a code']").set("R-10K\n")
    assert_selector "input[aria-label='Counted RC0603-10K']:focus", wait: 10
    find("input[aria-label='Counted RC0603-10K']").send_keys("47", :enter)
    assert_selector "tr", text: "RC0603-10K", wait: 10
    within("tr", text: "RC0603-10K") { assert_text "-3", wait: 10 }

    # Each scan adds one.
    find("button[role='switch'][id='stocktake-increment']").click
    3.times do |i|
      find("input[aria-label='Scan a code']").set("C-100N\n")
      assert_text "CL10B104: #{i + 1} counted.", wait: 10
    end
    within("tr", text: "CL10B104") { assert_text "-17" }

    click_on "Complete stocktake"
    within("[role='alertdialog']") { click_on "Complete and adjust stock" }
    assert_text "2 adjustments recorded", wait: 10

    assert_equal 47, PartStorage.find_by(part: @resistor, storage_location: @drawer).quantity
    assert_equal 3, PartStorage.find_by(part: @cap, storage_location: @drawer).quantity
    assert Stocktake.last.completed?
  end
end

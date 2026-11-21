require "application_system_test_case"

# Pages that pick one part search for it on the server (PartPicker) instead of
# shipping the whole inventory.
class PartPickerTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @drawer = create_storage_location(organization: @org, name: "Drawer 1", location_type: "drawer", code: "D1")
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RC0603-10K")
    @cap = create_part(organization: @org, name: "Cap 100nF", mpn: "CL10B104")
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "in", quantity_delta: 5)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "a new stock movement picks its part by searching" do
    visit stock_movements_path
    click_on "New Movement", match: :first

    within("[role='dialog']", text: "New movement") do
      find("button", text: "Select a part").click
    end
    find("input[placeholder='Search parts…']").send_keys("CL10")
    assert_no_selector "[role='option']", text: "Resistor 10k", wait: 5
    find("[role='option']", text: "Cap 100nF").click

    within("[role='dialog']", text: "New movement") do
      find("button", text: "Select a location").click
    end
    find("[role='option']", text: "Drawer 1").click
    within("[role='dialog']", text: "New movement") do
      find("input[inputmode]").fill_in(with: "3")
      click_on "Record movement"
    end

    assert_text "Cap 100nF", wait: 10
    assert_equal 3, PartStorage.find_by!(part: @cap, storage_location: @drawer).quantity
  end

  test "a stocktake adds a part found in the zone by searching" do
    stocktake = @org.stocktakes.new(user: @user, storage_location: @drawer)
    stocktake.save_with_generated_reference! { Stocktake.next_reference(@org) }
    stocktake.snapshot_stock!
    visit stocktake_path(stocktake)

    find("#stocktake-add-part").click
    find("input[placeholder='Search parts…']").send_keys("Cap")
    find("[role='option']", text: "Cap 100nF").click
    find("button[aria-label='Add part to the count']").click

    assert_text "Cap 100nF", wait: 10
    assert stocktake.stocktake_lines.exists?(part: @cap)
  end
end

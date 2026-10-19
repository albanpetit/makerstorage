require "application_system_test_case"

class QrLabelsTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @cabinet = create_storage_location(organization: @org, name: "Cabinet 1", location_type: "cabinet", code: "CAB-1")
    @drawer = create_storage_location(organization: @org, name: "Drawer 3", location_type: "drawer", parent: @cabinet)
    @other = create_storage_location(organization: @org, name: "Bench")
    @part = create_part(organization: @org, name: "NE555 timer", mpn: "NE555P")
    PartStorage.create!(part: @part, storage_location: @other, quantity: 200)
    PartStorage.create!(part: @part, storage_location: @drawer, quantity: 12)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "a zone opened by link prints labels for itself and its sub-zones" do
    current_window.resize_to(1280, 900)
    visit storage_locations_path(zone: @cabinet.id)
    assert_selector "h1", text: "Cabinet 1", wait: 10

    click_on "Label"
    within("[role='dialog']") do
      find("#label-sub-zones").click
      assert_button "Print 2 labels"
    end

    label_window = window_opened_by { within("[role='dialog']") { click_on "Print 2 labels" } }
    within_window(label_window) do
      assert_selector ".label", count: 2
      assert_selector ".label svg path", count: 2
      assert_text "CAB-1"
      assert_text "Drawer 3"
      assert_text "zone:#{@drawer.id}"
    end
  end

  test "scanning a zone label link lists its contents and counts a part in that zone" do
    visit scan_path(code: "http://printed.example:3000/scan?code=zone:#{@drawer.id}")

    assert_text "Drawer 3", wait: 10
    assert_text "Contents"
    find("button", text: "NE555P").click

    assert_text "NE555 timer", wait: 10
    # The count targets the scanned drawer, not the part's larger Bench stock.
    assert_selector "[data-slot='combobox-trigger']", text: "Cabinet 1 > Drawer 3"
  end
end

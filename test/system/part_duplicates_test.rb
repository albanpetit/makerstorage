require "application_system_test_case"

class PartDuplicatesTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org, name: "Timers")
    @drawer = create_storage_location(organization: @org, name: "Drawer 3")
    @keep = create_part(organization: @org, category: @category, name: "NE555 timer", mpn: "NE555P")
    @duplicate = create_part(organization: @org, category: @category, name: "555 (old entry)", sku: "ne-555p")
    @org.stock_movements.create!(part: @duplicate, storage_location: @drawer, movement_type: "in", quantity_delta: 4)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "merging a group found by the duplicate finder" do
    visit parts_path
    click_on "Duplicates"

    assert_selector "h1", text: "Duplicates"
    assert_text "Likely duplicates"
    assert_text "Same part number “NE555P”"

    within(:xpath, "//tr[.//text()[contains(., 'NE555 timer')]]") { click_on "Keep this one" }
    click_on "Merge 1 part"
    within("[role='alertdialog']") do
      assert_text "Merge 1 part into NE555 timer?"
      click_on "Merge"
    end

    assert_text "Merged 1 part into NE555 timer."
    assert_text "No duplicates found"
    assert_not Part.exists?(@duplicate.id)
    assert_equal 4, @keep.reload.total_quantity
  end

  test "merging parts picked in the inventory" do
    other = create_part(organization: @org, category: @category, name: "Timer chip")

    visit parts_path
    find("button[aria-label='Select #{@keep.name}']").click
    find("button[aria-label='Select #{other.name}']").click
    click_on "Merge"

    assert_selector "h1", text: "Merge parts"
    # Neither has any history: the oldest is kept.
    within(:xpath, "//tr[.//text()[contains(., 'NE555 timer')]]") { assert_text "Kept" }
    click_on "Merge 1 part"
    within("[role='alertdialog']") { click_on "Merge" }

    assert_selector "h1", text: "Inventory"
    assert_text "Merged 1 part into NE555 timer."
    assert_not Part.exists?(other.id)
  end
end

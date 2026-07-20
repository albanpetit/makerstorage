require "application_system_test_case"

class StorageLocationsMoveTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    cat = create_category(organization: @org)
    @from = create_storage_location(organization: @org, name: "Shelf A")
    @to = create_storage_location(organization: @org, name: "Shelf B")
    @part = create_part(organization: @org, category: cat, mpn: "RES-10K")
    PartStorage.create!(part: @part, storage_location: @from, quantity: 40)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "select components and move them to another zone in bulk" do
    current_window.resize_to(1280, 900)
    visit storage_locations_path
    assert_selector "h1", text: "Storage Zones", wait: 10

    # Shelf A is the first root and is selected by default; its component shows.
    assert_text "RES-10K"

    find("[aria-label='Select RES-10K']").click
    click_on "Move to…"
    assert_selector "[role='dialog']", wait: 5

    within("[role='dialog']") { find("button", text: "Choose a zone…").click }
    find("[role='option']", text: "Shelf B").click
    within("[role='dialog']") { click_on "Move" }

    assert_text "Moved 1 component to Shelf B", wait: 10
    assert_equal 0, PartStorage.find_by(part: @part, storage_location: @from).quantity
    assert_equal 40, PartStorage.find_by(part: @part, storage_location: @to).quantity
  end
end

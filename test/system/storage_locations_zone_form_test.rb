require "application_system_test_case"

class StorageLocationsZoneFormTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  # Regression: the new-zone dialog was a component defined inside the page, so it
  # remounted on every keystroke and the name input lost focus after one letter.
  test "can type a full zone name and create the zone" do
    visit storage_locations_path
    assert_selector "h1", text: "Storage Zones", wait: 10

    click_on "New Zone"
    assert_selector "[role='dialog']", wait: 5

    within("[role='dialog']") do
      fill_in "e.g. Box B2-T06", with: "Cabinet Alpha"
      # The whole value must survive — it would be truncated if focus were lost.
      assert_field "e.g. Box B2-T06", with: "Cabinet Alpha"
      click_on "Create zone"
    end

    assert_text "Storage zone created successfully", wait: 10
    assert StorageLocation.exists?(organization: @org, name: "Cabinet Alpha")
  end
end

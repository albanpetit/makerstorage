require "application_system_test_case"

class StorageLocationPickerTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @lab = create_storage_location(organization: @org, name: "Lab", location_type: "room")
    @cabinet = create_storage_location(organization: @org, name: "Cabinet", location_type: "cabinet", parent: @lab)
    @box = create_storage_location(organization: @org, name: "Box 3", location_type: "box", parent: @cabinet, code: "B2-T06")
    create_storage_location(organization: @org, name: "Attic", location_type: "room")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "searching zones by path or code and picking one with the keyboard" do
    visit parts_path(new: 1)
    find("#part-initial-location").click

    # The unfiltered list reads as a tree.
    assert_selector "[role='option']", text: "Cabinet"
    assert_selector "[role='option']", text: "Attic"

    search = find("input[placeholder='Search zones or codes…']")
    search.send_keys("lab box")
    assert_selector "[role='option']", text: "Box 3"
    assert_no_selector "[role='option']", text: "Attic"
    search.send_keys(:enter)
    assert_selector "#part-initial-location", text: "Lab > Cabinet > Box 3"

    find("#part-initial-location").click
    find("input[placeholder='Search zones or codes…']").send_keys("b2-t06", :enter)
    assert_selector "#part-initial-location", text: "Lab > Cabinet > Box 3"
  end

  test "creating a nested zone from the picker selects it" do
    visit parts_path(new: 1)
    find("#part-initial-location").click
    find("input[placeholder='Search zones or codes…']").send_keys("Lab > Cabinet > Drawer 1")
    find("[role='option']", text: 'Create zone "Lab > Cabinet > Drawer 1"').click

    within("[role='dialog']", text: "New storage zone") do
      assert_field "Name", with: "Drawer 1"
      assert_selector "#new-zone-parent", text: "Lab > Cabinet"
      click_on "Create zone"
    end

    assert_selector "#part-initial-location", text: "Lab > Cabinet > Drawer 1"
    assert_equal @cabinet.id, @org.storage_locations.find_by!(name: "Drawer 1").parent_id
  end
end

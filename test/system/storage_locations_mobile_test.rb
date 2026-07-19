require "application_system_test_case"

class StorageLocationsMobileTest < ApplicationSystemTestCase
  PHONE = [ 390, 844 ].freeze

  setup do
    @user = create_user
    @org = @user.organizations.first

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "empty state exposes the sidebar toggle on a phone" do
    current_window.resize_to(*PHONE)
    visit storage_locations_path

    assert_selector "h1", text: "Storage Zones", wait: 10
    assert_text "No storage zones yet"
    # Regression: the empty state used to render no header, hiding the nav
    # burger on mobile with no way to open the sidebar.
    assert_selector "button[data-sidebar='trigger']", visible: true
  end

  test "populated view uses master-detail navigation on a phone" do
    room = create_storage_location(organization: @org, name: "Main Room", location_type: "room")
    create_storage_location(organization: @org, name: "Cabinet A", location_type: "cabinet", parent: room)

    current_window.resize_to(*PHONE)
    visit storage_locations_path
    assert_selector "h1", text: "Storage Zones", wait: 10

    # Tree is shown first; the burger is available and the detail is hidden.
    assert_selector "button[data-sidebar='trigger']", visible: true
    assert_no_selector "button", text: "Back to zones"

    # Tapping a zone swaps to its detail with a back affordance.
    find(:xpath, "//div[normalize-space(.)='Cabinet A']").click
    assert_selector "button", text: "Back to zones", wait: 5

    # The layout must not overflow horizontally on a phone.
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"),
           "storage zones detail view overflows horizontally on a phone"

    # Back returns to the tree.
    click_on "Back to zones"
    assert_no_selector "button", text: "Back to zones"
  end
end

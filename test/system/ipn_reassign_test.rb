require "application_system_test_case"

class IpnReassignSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(ipn_generation_mode: "manual")
    box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    @in_bag = create_part(organization: @org, name: "NE555 timer", ipn: "MS-00001")
    @elsewhere = create_part(organization: @org, name: "LM358 op-amp", ipn: "MS-00002")
    @org.stock_movements.create!(part: @in_bag, storage_location: box.add_bags!(1).first, movement_type: "in", quantity_delta: 5)
    @org.update!(ipn_generation_mode: "box_bag")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an admin previews the bag codes before reassigning IPNs" do
    visit settings_path
    click_on "Numbering (IPN)"
    click_on "Preview & reassign"

    within "[role='alertdialog']" do
      assert_text "1 of 2 parts will change"
      assert_text "NE555 timer"
      assert_text "takes bag"
      assert_no_text "LM358 op-amp"

      find("#clear-unbagged").click
      assert_text "2 of 2 parts will change. 1 of them loses its reference."
      assert_text "LM358 op-amp"
      find("#clear-unbagged").click
      assert_text "1 of 2 parts will change"

      click_on "Reassign 1 IPN"
    end

    assert_text "Updated the IPN of 1 part", wait: 20
    assert_equal "A-1", @in_bag.reload.ipn
    assert_equal "MS-00002", @elsewhere.reload.ipn
  end
end

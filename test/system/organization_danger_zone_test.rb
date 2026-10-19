require "application_system_test_case"

class OrganizationDangerZoneSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @personal = @user.organizations.first
    @club = create_organization(name: "Club Robotique")
    OrganizationMembership.create!(organization: @club, user: @user, role: "owner")
    @part = create_part(organization: @club, name: "NE555 timer", mpn: "NE555P")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an owner resets an organization after typing its name" do
    visit settings_path
    click_on "Danger zone"
    click_on "Reset organization"

    within("[role='alertdialog']") do
      assert_button "Reset organization", disabled: true
      find("input[aria-label='Organization name']").set(@personal.name)
      click_on "Reset organization"
    end

    assert_text "was reset", wait: 20
    assert_equal @personal.id, @user.organizations.first.id
  end

  test "an owner merges an organization into another one they own" do
    find("[data-sidebar='header'] button", text: @personal.name).click
    find("[role='menuitem']", text: "Club Robotique").click
    assert_selector "[data-sidebar='header'] button", text: "Club Robotique", wait: 20

    visit settings_path
    click_on "Danger zone"
    find("[aria-label='Organization to merge into']").click
    find("[role='option']", text: @personal.name).click
    click_on "Merge"
    within("[role='alertdialog']") do
      find("input[aria-label='Organization name']").set("Club Robotique")
      click_on "Merge"
    end

    assert_text "was merged into", wait: 20
    assert_not Organization.exists?(@club.id)
    assert_equal @personal.id, @part.reload.organization_id
  end
end

require "application_system_test_case"

class LcscIntegrationSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an admin turns the LCSC lookup on and off from Settings" do
    visit settings_path
    click_on "Integrations"
    assert_text "LCSC Electronics"

    find("[role='switch'][aria-label='Search LCSC']").click
    assert_text "Settings updated successfully."
    assert_selector "[role='switch'][aria-label='Search LCSC'][aria-checked='true']"
    assert @org.reload.lcsc_enabled?

    find("[role='switch'][aria-label='Search LCSC']").click
    assert_selector "[role='switch'][aria-label='Search LCSC'][aria-checked='false']"
    refute @org.reload.lcsc_enabled?
  end
end

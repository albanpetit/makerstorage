require "application_system_test_case"

class KicadLibrarySettingsSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    create_part(organization: @org, category: create_category(organization: @org, name: "Resistors"))

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an admin turns the KiCad library on, gets the token once, then revokes it" do
    visit settings_path
    click_on "KiCad library"
    assert_text "1 part is available to KiCad."

    click_on "Enable & download library file"
    assert_text "Library file downloaded", wait: 20
    token = find("input[value^='#{KicadLibrary::TOKEN_PREFIX}']").value
    assert_equal @org, KicadLibrary.authenticate(token)
    assert_text "Last used by KiCad"

    click_on "Revoke"
    within("[role='alertdialog']") { click_on "Revoke" }
    assert_text "KiCad library access revoked", wait: 20
    assert_nil KicadLibrary.authenticate(token)
    assert_button "Enable & download library file"
  end
end

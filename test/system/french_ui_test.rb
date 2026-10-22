require "application_system_test_case"

class FrenchUiSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "a user switches the interface to French from their profile" do
    visit profile_path
    find("[aria-label='Language']").click
    find("[role='option']", text: "Français").click

    assert_text "Langue mise à jour."
    assert_selector "h1", text: "Profil"
    assert_equal "fr", @user.reload.locale
    assert_equal "fr", page.evaluate_script("document.documentElement.lang")

    visit root_path
    assert_selector "h1", text: "Tableau de bord"
    assert_link "Inventaire"

    visit profile_path
    find("[aria-label='Langue']").click
    find("[role='option']", text: "English").click
    assert_text "Language updated."
    assert_selector "h1", text: "Profile"
  end
end

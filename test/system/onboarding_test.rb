require "application_system_test_case"

# A new organization starts from a template on the dashboard, and a demo
# organization opens and goes away in one click.
class OnboardingTest < ApplicationSystemTestCase
  setup do
    @user = create_user(firstname: "Ada", lastname: "Lovelace")
    @org = @user.organizations.first

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "starting from a template, then the first steps" do
    assert_text "Start from a template"
    screenshot("1-modeles") if ENV["ONBOARDING_SCREENSHOTS"]
    click_on "Makerspace or fablab"

    assert_text "Template applied"
    assert_text "First steps"
    assert_text "2 of 7 done"
    assert_equal "makerspace", @org.reload.onboarding_template
    screenshot("2-premiers-pas") if ENV["ONBOARDING_SCREENSHOTS"]

    find("button[aria-label='Hide the first steps']").click
    assert_no_text "First steps"
    assert @org.reload.onboarding_dismissed_at
  end

  test "opening a demo and deleting it" do
    click_on "Explore a demo first"

    assert_text "This is a demo organization"
    assert_text "Demo workshop"
    assert_text "Needs attention"
    demo = @user.organizations.find_by!(demo: true)
    screenshot("3-demo") if ENV["ONBOARDING_SCREENSHOTS"]

    click_on "Delete the demo"
    assert_no_text "This is a demo organization"
    assert_not Organization.exists?(demo.id)
  end

  test "French" do
    @user.update!(locale: "fr")
    visit root_path

    assert_text "Partir d’un modèle"
    click_on "Salle de TP ou classe"
    assert_text "Premiers pas"
    assert @org.categories.exists?(name: "Plaques d’essai et prototypage")
    screenshot("4-francais") if ENV["ONBOARDING_SCREENSHOTS"]
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/onboarding/#{name}.png").to_s)
  end
end

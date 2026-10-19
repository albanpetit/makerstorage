require "application_system_test_case"

class CategoryPickerTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @passives = create_category(organization: @org, name: "Passives")
    @smd = create_category(organization: @org, name: "SMD", parent: @passives)
    create_category(organization: @org, name: "Actives")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "searching the category picker and picking a result with the keyboard" do
    visit parts_path(new: 1)
    find("#part-category").click

    # The unfiltered list reads as a tree.
    assert_selector "[role='option']", text: "Passives"
    assert_selector "[role='option']", text: "Actives"

    find("input[placeholder='Search categories…']").send_keys("smd")
    assert_selector "[role='option']", text: "SMD"
    assert_no_selector "[role='option']", text: "Actives"
    assert_selector "[role='option']", text: "Passives" # parent path shown next to SMD
    assert_no_text "Create category" # SMD already exists
    find("input[placeholder='Search categories…']").send_keys(:enter)

    assert_selector "#part-category", text: "Passives > SMD"
  end

  test "creating a nested category from the picker selects it" do
    visit parts_path(new: 1)
    find("#part-category").click
    find("input[placeholder='Search categories…']").send_keys("Passives > Capacitors")
    find("[role='option']", text: 'Create category "Passives > Capacitors"').click

    within("[role='dialog']", text: "New category") do
      assert_field "Name", with: "Capacitors"
      assert_selector "#new-category-parent", text: "Passives"
      click_on "Create category"
    end

    assert_selector "#part-category", text: "Passives > Capacitors"
    assert_equal @passives.id, @org.categories.find_by!(name: "Capacitors").parent_id
  end
end

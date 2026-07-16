require "application_system_test_case"

class PartsBulkActionsTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @old_category = create_category(organization: @org, name: "Resistors")
    @new_category = create_category(organization: @org, name: "Capacitors")
    @part_a = create_part(organization: @org, category: @old_category, name: "Part A")
    @part_b = create_part(organization: @org, category: @old_category, name: "Part B")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 10
  end

  test "selecting parts and applying a bulk category change" do
    visit parts_path
    assert_selector "table", wait: 10

    find("button[aria-label='Select #{@part_a.name}']").click
    find("button[aria-label='Select #{@part_b.name}']").click

    assert_text "2 selected"

    click_on "Category"
    find("#bulk-category").click
    find("[role='option']", text: @new_category.name).click
    click_on "Set category"

    within("[role='alertdialog']") { click_on "Set category" }

    assert_text "Set category to #{@new_category.name} for 2 parts."
    assert_no_text "2 selected"

    within(:xpath, "//tr[.//text()[contains(., '#{@part_a.name}')]]") do
      assert_text @new_category.name
    end
    within(:xpath, "//tr[.//text()[contains(., '#{@part_b.name}')]]") do
      assert_text @new_category.name
    end
  end
end

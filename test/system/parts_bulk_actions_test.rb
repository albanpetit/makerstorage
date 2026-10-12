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
    assert_selector "h1", text: "Dashboard", wait: 20
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

  test "printed labels show part data as text, never as markup" do
    payload = %(<img src=x onerror="window.opener.__xss = true">Evil)
    create_part(organization: @org, category: @old_category, name: payload)

    visit parts_path
    assert_selector "table", wait: 10
    find("button[aria-label='Select #{payload}']").click

    click_on "Labels"
    label_window = window_opened_by { within("[role='dialog']") { click_on "Print 1 label" } }
    within_window(label_window) do
      assert_text payload
      assert_no_selector "img"
    end

    assert_not page.evaluate_script("window.__xss === true")
  end

  test "part labels carry a QR code linking the scanner to the part's IPN" do
    @part_a.update!(ipn: "MS-00042")

    visit parts_path
    assert_selector "table", wait: 10
    find("button[aria-label='Select #{@part_a.name}']").click

    click_on "Labels"
    find("#label-format").click
    find("[role='option']", text: "Brother DK-11209").click

    label_window = window_opened_by { within("[role='dialog']") { click_on "Print 1 label" } }
    within_window(label_window) do
      assert_text "MS-00042"
      assert_text @part_a.name
      assert_selector ".label svg path"
      assert_includes page.html, "size:62mm 29mm"
    end
  end
end

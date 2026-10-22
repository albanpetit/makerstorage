require "application_system_test_case"

# Reviewing the thresholds suggested by consumption, from the Alerts page and
# from a part's detail.
class ThresholdSuggestionsTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @shelf = create_storage_location(organization: @org, name: "Shelf", code: "S1")
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RC0603FR-0710KL", min_stock_threshold: 10)
    @led = create_part(organization: @org, name: "Red LED", mpn: "LTST-C191KRKT", min_stock_threshold: 200)
    stock(@resistor, 1000, days_ago: 200)
    stock(@led, 400, days_ago: 200)
    [ 80, 40, 30, 20 ].each_with_index { |quantity, i| use(@resistor, quantity, days_ago: 10 + i * 25) }
    [ 6, 4 ].each_with_index { |quantity, i| use(@led, quantity, days_ago: 15 + i * 30) }

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "applying suggestions from the list" do
    visit alerts_path
    click_on "Suggested thresholds"

    assert_selector "h1", text: "Suggested thresholds"
    assert_text "RC0603FR-0710KL"
    assert_text "LTST-C191KRKT"
    screenshot("1-liste") if ENV["THRESHOLD_SCREENSHOTS"]

    find("[aria-label='Select all']").click
    click_on "Apply to 2 components"
    assert_text "Thresholds updated on 2 components."
    assert_equal 57, @resistor.reload.min_stock_threshold
    assert_equal 4, @led.reload.min_stock_threshold
    assert_text "Every threshold is in line with recent use."
  end

  test "the part detail shows consumption and applies its suggestion" do
    visit threshold_suggestions_path
    click_on "RC0603FR-0710KL"

    within("[role='dialog']") do
      assert_text "Consumption"
      assert_text "Suggested threshold 57"
      if ENV["THRESHOLD_SCREENSHOTS"]
        sleep 0.6 # let the sheet finish sliding in
        screenshot("2-fiche")
      end
      click_on "Use 57"
    end
    assert_selector "[role='dialog']", text: "▲ threshold 57"
    assert_equal 57, @resistor.reload.min_stock_threshold
  end

  private

  def stock(part, quantity, days_ago:)
    StockMovement.create!(organization: @org, part: part, storage_location: @shelf, movement_type: "in",
                          quantity_delta: quantity, created_at: days_ago.days.ago)
  end

  def use(part, quantity, days_ago:)
    StockMovement.create!(organization: @org, part: part, storage_location: @shelf, movement_type: "out",
                          quantity_delta: -quantity, reason: "Build", created_at: days_ago.days.ago)
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/thresholds-#{name}.png").to_s)
  end
end

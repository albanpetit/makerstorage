require "application_system_test_case"

class DecimalQuantitiesTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @shelf = create_storage_location(organization: @org, name: "Filament shelf")
    @filament = create_part(organization: @org, name: "PLA filament black", mpn: "PLA-BLK", unit: "gram", pack_size: 1000, min_stock_threshold: 500)
    StockMovement.create!(organization: @org, part: @filament, storage_location: @shelf, movement_type: "in", quantity_delta: 340.5)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "stock of a part counted in grams is shown and added in packs" do
    visit parts_path
    assert_text "340.5 g"
    click_on "PLA-BLK"

    within("[role='dialog']") do
      assert_text "340.5 g"
      click_on "Stock in"
    end
    within("[role='dialog']", text: "Record movement") do
      click_on "1 pack (1,000 g)"
      assert_field with: "1000"
      click_on "Record movement"
    end

    assert_text "1,340.5 g", wait: 10
    assert_equal 1340.5, @filament.reload.total_quantity
    save_screenshot("/tmp/claude-0/shots/1-fiche.png") if ENV["SHOTS"]
  end
end

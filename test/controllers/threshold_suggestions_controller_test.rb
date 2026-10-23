require "test_helper"

class ThresholdSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(timezone: "Etc/UTC")
    @shelf = create_storage_location(organization: @org, name: "Shelf")
    travel_to Time.utc(2026, 10, 22, 12)

    # 2 a day over 90 days: suggests 60.
    @busy = create_part(organization: @org, name: "Busy resistor", min_stock_threshold: 10)
    stock(@busy, 400, days_ago: 120)
    use(@busy, 100, days_ago: 60)
    use(@busy, 80, days_ago: 10)
    # 1 a day: suggests 30, already set.
    @steady = create_part(organization: @org, name: "Steady LED", min_stock_threshold: 30)
    stock(@steady, 200, days_ago: 120)
    use(@steady, 45, days_ago: 50)
    use(@steady, 45, days_ago: 5)
    # A single use: no suggestion.
    @once = create_part(organization: @org, name: "Once diode", min_stock_threshold: 5)
    stock(@once, 50, days_ago: 120)
    use(@once, 20, days_ago: 3)
    @idle = create_part(organization: @org, name: "Idle cap")
    stock(@idle, 50, days_ago: 120)
  end

  test "redirects a signed-out visitor to login" do
    get threshold_suggestions_path
    assert_redirected_to new_user_session_path
  end

  test "index lists used parts with their consumption, the ones to review first" do
    sign_in @user
    get threshold_suggestions_path
    assert_response :success

    props = inertia_props
    assert_equal 90, props["window_days"]
    assert_equal 30, props["cover_days"]
    assert_equal [ @busy.id, @steady.id, @once.id ], props["rows"].map { |row| row["id"] }

    busy = props["rows"].first
    assert_equal true, busy["differs"]
    assert_equal 180, busy["consumed"]
    assert_equal 2, busy["movements"]
    assert_equal 60, busy["suggested_threshold"]
    assert_equal 10, busy["min_stock_threshold"]
    assert_equal 220, busy["quantity"]
    assert_equal 110, busy["days_left"]
    assert_equal 60.0, busy["monthly_rate"]

    assert_equal false, props["rows"].second["differs"]
    assert_nil props["rows"].third["suggested_threshold"]
  end

  test "apply sets the suggested thresholds, skipping parts without one and other organizations' parts" do
    other_part = create_part(organization: create_organization, min_stock_threshold: 3)
    sign_in @user

    post apply_threshold_suggestions_path, params: { part_ids: [ @busy.id, @once.id, @idle.id, other_part.id ] }
    assert_redirected_to threshold_suggestions_path
    assert_equal "Threshold updated on 1 component.", flash[:notice]
    assert_equal 60, @busy.reload.min_stock_threshold
    assert_equal 5, @once.reload.min_stock_threshold
    assert_equal 3, other_part.reload.min_stock_threshold
  end

  test "apply asks for a selection" do
    sign_in @user
    post apply_threshold_suggestions_path, params: { part_ids: [] }
    assert_equal "Select at least one component.", flash[:alert]
  end

  test "a viewer sees the suggestions but can't apply them" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post switch_organization_path(@org)

    get threshold_suggestions_path
    assert_response :success

    assert_equal [ @busy.id, @steady.id, @once.id ], inertia_props["rows"].map { |row| row["id"] }

    post apply_threshold_suggestions_path, params: { part_ids: [ @busy.id ] }
    assert_equal "Your role is read-only for this organization.", flash[:alert]
    assert_equal 10, @busy.reload.min_stock_threshold
  end

  test "the part detail carries its consumption" do
    sign_in @user
    get part_path(@busy), headers: { "Accept" => "application/json" }
    assert_response :success

    consumption = JSON.parse(response.body)["consumption"]
    assert_equal 90, consumption["window_days"]
    assert_equal 180, consumption["consumed"]
    assert_equal 60, consumption["suggested_threshold"]
    assert_equal 30, consumption["cover_days"]
    assert_equal 6, consumption["months"].size
    assert_equal({ "month" => "2026-10", "quantity" => 80 }, consumption["months"].last)

    get part_path(@idle), headers: { "Accept" => "application/json" }
    consumption = JSON.parse(response.body)["consumption"]
    assert_equal 0, consumption["consumed"]
    assert_nil consumption["suggested_threshold"]
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

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

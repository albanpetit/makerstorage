require "test_helper"

class StockValuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @zone = create_storage_location(organization: @org, name: "Lab")
    @part = create_part(organization: @org, name: "MCU", mpn: "=MCU-1", unit_price: 3)
    StockMovement.create!(organization: @org, part: @part, storage_location: @zone, movement_type: "in", quantity_delta: 10)
  end

  test "shows the stock value by category, zone and part" do
    sign_in @user
    get stock_value_path

    assert_response :success
    props = inertia_props
    assert_equal "current", props["valuation_method"]
    assert_equal 30.0, props["total"]
    assert_equal 1, props["parts_count"]
    assert_equal [ "Lab" ], props["zones"].map { |zone| zone["name"] }
    assert_equal [ @part.id ], props["parts"].map { |part| part["id"] }
    assert_equal 3.0, props["parts"].first["unit_value"]
  end

  test "values at purchase prices on request" do
    order = create_order(organization: @org)
    order.order_lines.create!(part: @part, quantity: 10, unit_price: 2)
    order.update_column(:status, "received")
    sign_in @user

    get stock_value_path(method: "last")

    assert_equal "last", inertia_props["valuation_method"]
    assert_equal 20.0, inertia_props["total"]
    assert_equal 1, inertia_props["purchase_priced_count"]
  end

  test "exports every part as CSV, escaping formula-like text" do
    sign_in @user
    get stock_value_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal [ "Part", "IPN", "Name", "Category", "Quantity", "Unit value", "Value", "Price source" ], rows.first
    assert_equal [ "'=MCU-1", @part.ipn, "MCU" ], rows.second.first(3)
    assert_equal [ "10", "3.0", "30.0", "current" ], rows.second.last(4)
  end

  test "viewers can see it" do
    viewer = create_user
    OrganizationMembership.create!(user: viewer, organization: @org, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    get stock_value_path
    assert_response :success
    assert_equal 30.0, inertia_props["total"]
  end

  test "another organization's stock never shows" do
    other_user = create_user
    sign_in other_user
    get stock_value_path

    assert_equal 0.0, inertia_props["total"]
    assert_empty inertia_props["parts"]
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

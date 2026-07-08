require "test_helper"

class StockMovementsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get stock_movements_path
    assert_redirected_to new_user_session_path
  end

  test "index computes the running stock balance after each movement" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org, name: "Shelf A")
    part = create_part(organization: org, category: category, mpn: "RES-10K")

    first = StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 50)
    second = StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "out", quantity_delta: -20)

    sign_in user
    get stock_movements_path
    assert_response :success

    movements = inertia_props["movements"]
    first_json = movements.find { |m| m["id"] == first.id }
    second_json = movements.find { |m| m["id"] == second.id }
    assert_equal 50, first_json["balance_after"]
    assert_equal 30, second_json["balance_after"]
    assert_equal "RES-10K", first_json["part"]["reference"]
    assert_equal "Shelf A", first_json["location_name"]
  end

  test "index does not leak another organization's movements" do
    user = create_user
    other_org = create_organization
    other_category = create_category(organization: other_org)
    other_location = create_storage_location(organization: other_org)
    other_part = create_part(organization: other_org, category: other_category)
    StockMovement.create!(organization: other_org, part: other_part, storage_location: other_location, movement_type: "in", quantity_delta: 10)

    sign_in user
    get stock_movements_path
    assert_response :success
    assert_empty inertia_props["movements"]
  end

  test "create records an inbound movement from a positive quantity" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      post stock_movements_path, params: {
        stock_movement: { part_id: part.id, storage_location_id: location.id, movement_type: "in", quantity: "40", reason: "Restock" }
      }
    end

    assert_redirected_to stock_movements_path
    movement = StockMovement.last
    assert_equal 40, movement.quantity_delta
    assert_equal user, movement.user
  end

  test "create records an outbound movement as a negative delta" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 100)

    sign_in user
    post stock_movements_path, params: {
      stock_movement: { part_id: part.id, storage_location_id: location.id, movement_type: "out", quantity: "30" }
    }

    assert_equal(-30, StockMovement.last.quantity_delta)
  end

  test "create records an adjustment with a decrease direction as a negative delta" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 100)

    sign_in user
    post stock_movements_path, params: {
      stock_movement: { part_id: part.id, storage_location_id: location.id, movement_type: "adjustment", direction: "decrease", quantity: "5" }
    }

    assert_equal(-5, StockMovement.last.quantity_delta)
  end

  test "create redirects back with errors when the movement is invalid" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)

    sign_in user
    assert_no_difference "StockMovement.count" do
      post stock_movements_path,
        params: { stock_movement: { part_id: part.id, storage_location_id: location.id, movement_type: "out", quantity: "10" } },
        headers: { "HTTP_REFERER" => stock_movements_url }
    end

    assert_redirected_to stock_movements_path
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

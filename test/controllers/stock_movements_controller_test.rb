require "test_helper"
require "csv"

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

  test "index paginates the ledger newest first with balances over full history" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)

    page_size = StockMovementsController::PAGE_SIZE
    base = Time.current.change(usec: 0)
    (page_size + 3).times do |i|
      StockMovement.create!(organization: org, part: part, storage_location: location,
        movement_type: "in", quantity_delta: 1, created_at: base + i.seconds)
    end

    sign_in user
    get stock_movements_path
    assert_response :success
    props = inertia_props
    assert_equal page_size, props["movements"].size
    assert_equal 1, props["pagination"]["page"]
    assert_equal 2, props["pagination"]["page_count"]
    assert_equal page_size + 3, props["pagination"]["total"]
    # Newest movement is first and its balance equals the whole running total.
    assert_equal page_size + 3, props["movements"].first["balance_after"]

    get stock_movements_path(page: 2)
    page_two = inertia_props
    assert_equal 3, page_two["movements"].size
    # The oldest movement lands on the last page with balance 1 — proving the
    # running balance is computed over the full ledger, not just the page.
    assert_equal 1, page_two["movements"].last["balance_after"]
  end

  test "index filters by movement type while balances still reflect every movement" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)

    base = Time.current.change(usec: 0)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 100, created_at: base)
    outbound = StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "out", quantity_delta: -30, created_at: base + 1.second)

    sign_in user
    get stock_movements_path(type: "out")
    assert_response :success
    props = inertia_props
    assert_equal "out", props["filter"]
    assert_equal [ outbound.id ], props["movements"].map { |m| m["id"] }
    assert_equal 70, props["movements"].first["balance_after"]
  end

  test "index stats aggregate the whole ledger regardless of the active filter" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category)

    base = Time.current.change(usec: 0)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 100, created_at: base)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 50, created_at: base + 1.second)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "out", quantity_delta: -30, created_at: base + 2.seconds)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "adjustment", quantity_delta: -5, created_at: base + 3.seconds)

    sign_in user
    get stock_movements_path(type: "in")
    stats = inertia_props["stats"]
    assert_equal 150, stats["inbound"]
    assert_equal 30, stats["outbound"]
    assert_equal 4, stats["total"]
    assert_equal 2, stats["in_count"]
    assert_equal 1, stats["out_count"]
    assert_equal 1, stats["adjustment_count"]
  end

  test "export streams a CSV of every movement matching the active filter" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org, name: "Shelf A")
    part = create_part(organization: org, category: category, mpn: "RES-10K")

    base = Time.current.change(usec: 0)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 100, created_at: base)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "out", quantity_delta: -30, created_at: base + 1.second)

    sign_in user
    get export_stock_movements_path(type: "out")
    assert_response :success
    assert_equal "text/csv", @response.media_type

    rows = CSV.parse(@response.body)
    assert_equal [ "Date", "Type", "Reference", "Reason", "Location", "User", "Quantity", "Stock After" ], rows.first
    assert_equal 2, rows.size
    data = rows.last
    assert_equal "out", data[1]
    assert_equal "RES-10K", data[2]
    assert_equal "Shelf A", data[4]
    assert_equal "-30", data[6]
    assert_equal "70", data[7]
  end

  test "export neutralizes spreadsheet formulas in user-entered text" do
    user = create_user
    org = user.organizations.first
    location = create_storage_location(organization: org, name: "@Shelf")
    part = create_part(organization: org)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in",
                          quantity_delta: 5, reason: "=HYPERLINK(\"http://evil.example\")")
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "out",
                          quantity_delta: -2, reason: "-picked")

    sign_in user
    get export_stock_movements_path

    rows = CSV.parse(@response.body).drop(1).sort_by { |row| row[6].to_i }
    out_row, in_row = rows
    assert_equal "'=HYPERLINK(\"http://evil.example\")", in_row[3]
    assert_equal "'@Shelf", in_row[4]
    assert_equal "'-picked", out_row[3]
    assert_equal "-2", out_row[6], "numeric quantities stay numbers"
  end

  test "export does not leak another organization's movements" do
    user = create_user
    other_org = create_organization
    other_category = create_category(organization: other_org)
    other_location = create_storage_location(organization: other_org)
    other_part = create_part(organization: other_org, category: other_category)
    StockMovement.create!(organization: other_org, part: other_part, storage_location: other_location, movement_type: "in", quantity_delta: 10)

    sign_in user
    get export_stock_movements_path
    assert_response :success
    assert_equal 1, CSV.parse(@response.body).size
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

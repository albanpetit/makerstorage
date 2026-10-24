require "test_helper"

# Parts counted in a measure (meters, grams, liters…) take decimal quantities
# everywhere stock moves; parts counted in pieces stay whole (see Quantity).
class DecimalQuantitiesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @shelf = create_storage_location(organization: @org, name: "Shelf A")
    @bench = create_storage_location(organization: @org, name: "Bench")
    @wire = create_part(organization: @org, name: "Hookup wire 22AWG", mpn: "WIRE-22", unit: "meter")
    @resistor = create_part(organization: @org, name: "Resistor 10k", mpn: "RES-10K")
    stock(@wire, 10, @shelf)
    stock(@resistor, 10, @shelf)
    sign_in @user
  end

  test "a part's unit and pack size are saved from the part form" do
    patch part_path(@resistor), params: { part: { unit: "gram", pack_size: "1000", min_stock_threshold: "250,5" } }

    @resistor.reload
    assert_equal [ "gram", 1000, 250.5 ], [ @resistor.unit, @resistor.pack_size, @resistor.min_stock_threshold ]

    get edit_part_path(@resistor, format: :json)
    part = response.parsed_body["part"]
    assert_equal [ "gram", 1000, 250.5 ], part.values_at("unit", "pack_size", "min_stock_threshold")
  end

  test "stock movements take a decimal, with a French comma, for a measure only" do
    post stock_movements_path, params: { stock_movement: { part_id: @wire.id, storage_location_id: @shelf.id, movement_type: "out", quantity: "2,5" } }
    assert_redirected_to stock_movements_path
    assert_equal(-2.5, StockMovement.last.quantity_delta)
    assert_equal 7.5, @wire.reload.total_quantity

    assert_no_difference -> { StockMovement.count } do
      post stock_movements_path, params: { stock_movement: { part_id: @resistor.id, storage_location_id: @shelf.id, movement_type: "out", quantity: "2.5" } }
    end
    assert_equal 10, @resistor.reload.total_quantity

    get stock_movements_path
    movement = inertia_props["movements"].find { |m| m["part"]["id"] == @wire.id && m["quantity_delta"].negative? }
    assert_equal [ -2.5, 7.5, "meter" ], [ movement["quantity_delta"], movement["balance_after"], movement["part"]["unit"] ]
  end

  test "the part sheet sends the unit and decimal stock" do
    stock(@wire, 0.25, @bench)

    get part_path(@wire, format: :json)
    body = response.parsed_body
    assert_equal [ 10.25, "meter" ], body["part"].values_at("total_quantity", "unit")
    assert_equal [ 10, 0.25 ], body["storages"].map { |storage| storage["quantity"] }.sort.reverse
  end

  test "moving part of a measure between zones" do
    post move_stock_storage_locations_path, params: { from_location_id: @shelf.id, to_location_id: @bench.id, moves: [ { part_id: @wire.id, quantity: "3.75" } ] }

    assert_equal 6.25, PartStorage.find_by!(part: @wire, storage_location: @shelf).quantity
    assert_equal 3.75, PartStorage.find_by!(part: @wire, storage_location: @bench).quantity
  end

  test "stocktake counts a measure to the thousandth" do
    stocktake = @org.stocktakes.create!(storage_location: @shelf, user: @user, reference: "ST-1")
    stocktake.snapshot_stock!
    line = stocktake.stocktake_lines.find_by!(part: @wire)

    patch stocktake_stocktake_line_path(stocktake, line), params: { stocktake_line: { counted_quantity: "9,875" } }
    assert_equal 9.875, line.reload.counted_quantity
    assert_equal(-0.125, line.difference)

    resistor_line = stocktake.stocktake_lines.find_by!(part: @resistor)
    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "9.5" } }
    assert_nil resistor_line.reload.counted_quantity
    assert_match "whole number", flash[:alert]
  end

  test "lending and returning a measure" do
    post loans_path, params: { loan: { borrower_name: "Alice", lines: [ { part_id: @wire.id, storage_location_id: @shelf.id, quantity: "1,5" } ] } }
    loan = Loan.last
    assert_equal 1.5, loan.loan_lines.first.quantity
    assert_equal 8.5, @wire.reload.total_quantity

    post return_items_loan_path(loan), params: { lines: [ { line_id: loan.loan_lines.first.id, quantity: "0.5", storage_location_id: @shelf.id } ] }
    assert_equal 1, loan.reload.outstanding_quantity
    assert_equal 9, @wire.reload.total_quantity
    assert_not loan.closed?
  end

  test "a build draws decimal BOM quantities across zones" do
    stock(@wire, 0.3, @bench)
    project = create_project(organization: @org)
    project.project_lines.create!(part: @wire, quantity: 0.2, match_type: "manual", designation: "Wire")

    post build_project_path(project), params: { kits: 3, builds_count: 0 }

    assert_equal 9.7, @wire.reload.total_quantity
    assert_equal(-0.6, StockMovement.where(part: @wire, project_build: project.project_builds.last).sum(:quantity_delta))
  end

  test "order lines take a decimal quantity and receive it into stock" do
    order = create_order(organization: @org)
    post order_order_lines_path(order), params: { order_line: { part_id: @wire.id, quantity: "25,5" } }
    assert_equal 25.5, order.order_lines.find_by!(part: @wire).quantity

    post order_order_lines_path(order), params: { order_line: { part_id: @resistor.id, quantity: "1.5" } }
    assert_nil order.order_lines.find_by(part: @resistor)

    order.advance!(user: @user)
    order.advance!(user: @user)
    assert_equal 35.5, @wire.reload.total_quantity
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  def stock(part, quantity, location)
    StockMovement.create!(organization: @org, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end
end

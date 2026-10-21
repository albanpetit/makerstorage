require "test_helper"

class StocktakesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @cabinet = create_storage_location(organization: @org, name: "Cabinet", location_type: "cabinet", code: "CAB")
    @drawer = create_storage_location(organization: @org, name: "Drawer 1", location_type: "drawer", code: "D1", parent: @cabinet)
    @shelf = create_storage_location(organization: @org, name: "Shelf", code: "SH")
    @resistor = create_part(organization: @org, name: "Resistor 10k", ipn: "R-10K", unit_price: 0.5)
    @cap = create_part(organization: @org, name: "Cap 100nF", ipn: "C-100N")
    stock(@resistor, @drawer, 50)
    stock(@cap, @cabinet, 10)
    stock(@cap, @drawer, 4)
    sign_in @user
  end

  test "redirects a signed-out visitor to login" do
    sign_out @user
    get stocktakes_path
    assert_redirected_to new_user_session_path
  end

  test "index lists stocktakes and the zones due for a count" do
    stocktake = start(@shelf)
    stocktake.complete!(user: @user)
    create_storage_location(organization: @org, name: "Empty room")

    get stocktakes_path
    assert_response :success

    props = inertia_props
    assert_equal [ stocktake.reference ], props["stocktakes"].map { |s| s["reference"] }
    # The shelf holds nothing; the cabinet and drawer hold stock and were never counted.
    assert_equal [ "Cabinet", "Cabinet > Drawer 1" ], props["due_zones"].map { |zone| zone["name"] }
    assert_equal Stocktake::DEFAULT_DUE_AFTER_DAYS, props["due_after"]
  end

  test "a zone counted recently is no longer due" do
    travel_to 40.days.ago do
      start(@cabinet).complete!(user: @user)
    end

    get stocktakes_path
    assert_empty inertia_props["due_zones"]

    get stocktakes_path(due_after: 30)
    assert_equal 2, inertia_props["due_zones"].size
    assert inertia_props["due_zones"].all? { |zone| zone["last_counted_at"] }
  end

  test "index does not leak another organization's stocktakes" do
    other = create_organization
    zone = create_storage_location(organization: other)
    foreign = other.stocktakes.create!(storage_location: zone, reference: "ST-OTHER")

    get stocktakes_path
    assert_not_includes inertia_props["stocktakes"].map { |s| s["reference"] }, "ST-OTHER"

    get stocktake_path(foreign)
    assert_response :not_found
  end

  test "create starts a count of the zone with its sub-zones" do
    assert_difference -> { Stocktake.count } => 1, -> { StocktakeLine.count } => 3 do
      post stocktakes_path, params: { stocktake: { storage_location_id: @cabinet.id, include_sub_zones: "true", blind: "true", notes: "Monthly" } }
    end

    stocktake = Stocktake.last
    assert_redirected_to stocktake_path(stocktake)
    assert_equal @user, stocktake.user
    assert stocktake.blind
    assert_equal "Monthly", stocktake.notes
  end

  test "create refuses a zone already being counted" do
    start(@drawer)

    assert_no_difference -> { Stocktake.count } do
      post stocktakes_path, params: { stocktake: { storage_location_id: @cabinet.id } }
    end
    assert_match(/already being counted/, flash[:alert])
  end

  test "create refuses another organization's zone" do
    foreign = create_storage_location(organization: create_organization)

    assert_no_difference -> { Stocktake.count } do
      post stocktakes_path, params: { stocktake: { storage_location_id: foreign.id } }
    end
    assert_match(/Pick the zone/, flash[:alert])
  end

  test "show hides expected quantities of uncounted lines in a blind count" do
    stocktake = start(@cabinet, blind: true)
    stocktake.count!(line(stocktake, @cap, @cabinet), 9, user: @user)

    get stocktake_path(stocktake)
    lines = inertia_props["lines"].index_by { |l| [ l["part"]["id"], l["zone"]["id"] ] }
    assert_nil lines[[ @resistor.id, @drawer.id ]]["expected_quantity"]
    assert_equal 10, lines[[ @cap.id, @cabinet.id ]]["expected_quantity"]
    assert_equal(-1, lines[[ @cap.id, @cabinet.id ]]["difference"])
  end

  test "show summarises the differences and their value" do
    stocktake = start(@cabinet)
    stocktake.count!(line(stocktake, @resistor, @drawer), 46, user: @user)
    stocktake.count!(line(stocktake, @cap, @cabinet), 12, user: @user)

    get stocktake_path(stocktake, zone: @drawer.id)
    summary = inertia_props["stocktake"]
    assert_equal 2, summary["counted_count"]
    assert_equal 2, summary["discrepancy_count"]
    assert_equal 2, summary["units_found"]
    assert_equal 4, summary["units_missing"]
    assert_equal(-2.0, summary["value_difference"])
    assert_equal @drawer.id, inertia_props["current_zone_id"]
  end

  test "scanning a part code with increment counts one more" do
    stocktake = start(@cabinet)

    post scan_stocktake_path(stocktake), params: { code: "r-10k", increment: "true" }
    post scan_stocktake_path(stocktake), params: { code: "R-10K", increment: "true" }

    resistor_line = line(stocktake, @resistor, @drawer)
    assert_redirected_to stocktake_path(stocktake, line: resistor_line.id)
    assert_equal 2, resistor_line.counted_quantity
  end

  test "scanning a printed label link opens the line without counting" do
    stocktake = start(@cabinet)

    post scan_stocktake_path(stocktake), params: { code: "https://example.org/scan?code=R-10K" }

    resistor_line = line(stocktake, @resistor, @drawer)
    assert_redirected_to stocktake_path(stocktake, line: resistor_line.id)
    assert_not resistor_line.counted?
  end

  test "a part stocked in several counted zones needs the zone first" do
    stocktake = start(@cabinet)

    post scan_stocktake_path(stocktake), params: { code: "C-100N", increment: "true" }
    assert_match(/several zones/, flash[:alert])

    post scan_stocktake_path(stocktake), params: { code: "C-100N", zone: @drawer.id, increment: "true" }
    assert_equal 1, line(stocktake, @cap, @drawer).counted_quantity
    assert_not line(stocktake, @cap, @cabinet).counted?
  end

  test "scanning a zone code makes it the zone being counted" do
    stocktake = start(@cabinet)

    post scan_stocktake_path(stocktake), params: { code: "d1" }
    assert_redirected_to stocktake_path(stocktake, zone: @drawer.id)

    post scan_stocktake_path(stocktake), params: { code: "SH" }
    assert_match(/isn't part of this stocktake/, flash[:alert])
  end

  test "scanning a part found where the ledger had none adds a line in the current zone" do
    stocktake = start(@cabinet)

    assert_difference -> { StocktakeLine.count }, 1 do
      post scan_stocktake_path(stocktake), params: { code: "R-10K", zone: @cabinet.id, increment: "true" }
    end
    added = line(stocktake, @resistor, @cabinet)
    assert_equal 0, added.expected_quantity
    assert_equal 1, added.counted_quantity
  end

  test "scanning an unknown code says so" do
    stocktake = start(@cabinet)

    post scan_stocktake_path(stocktake), params: { code: "NOPE" }
    assert_match(/No part or zone matches "NOPE"/, flash[:alert])
  end

  test "a line's count is saved and can be cleared" do
    stocktake = start(@cabinet)
    resistor_line = line(stocktake, @resistor, @drawer)

    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "48" } }
    assert_equal 48, resistor_line.reload.counted_quantity
    assert_equal @user, resistor_line.counted_by

    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "" } }
    assert_not resistor_line.reload.counted?
  end

  test "an invalid count is refused" do
    stocktake = start(@cabinet)
    resistor_line = line(stocktake, @resistor, @drawer)

    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "-3" } }
    assert_match(/Could not save that count/, flash[:alert])
    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "2.5" } }
    assert_not resistor_line.reload.counted?
  end

  test "adding a part puts it on the count in the chosen zone" do
    stocktake = start(@cabinet)

    assert_difference -> { StocktakeLine.count }, 1 do
      post stocktake_stocktake_lines_path(stocktake), params: { stocktake_line: { part_id: @resistor.id, storage_location_id: @cabinet.id } }
    end
    added = line(stocktake, @resistor, @cabinet)
    assert_redirected_to stocktake_path(stocktake, zone: @cabinet.id, line: added.id)
  end

  test "adding a part outside the counted zones is refused" do
    stocktake = start(@drawer)

    assert_no_difference -> { StocktakeLine.count } do
      post stocktake_stocktake_lines_path(stocktake), params: { stocktake_line: { part_id: @resistor.id, storage_location_id: @shelf.id } }
    end
    assert_match(/isn't part of this stocktake/, flash[:alert])
  end

  test "lines can't target another organization's part" do
    stocktake = start(@cabinet)
    foreign = create_part(organization: create_organization)

    assert_no_difference -> { StocktakeLine.count } do
      post stocktake_stocktake_lines_path(stocktake), params: { stocktake_line: { part_id: foreign.id, storage_location_id: @cabinet.id } }
    end
    assert_response :not_found
  end

  test "complete adjusts stock to the count" do
    stocktake = start(@cabinet)
    stocktake.count!(line(stocktake, @resistor, @drawer), 45, user: @user)

    assert_difference -> { StockMovement.count }, 1 do
      post complete_stocktake_path(stocktake)
    end
    assert_redirected_to stocktake_path(stocktake)
    assert_match(/1 adjustment recorded/, flash[:notice])
    assert_equal 45, quantity(@resistor, @drawer)
    assert_equal 10, quantity(@cap, @cabinet)
    assert stocktake.reload.completed?
  end

  test "complete can take uncounted lines as empty" do
    stocktake = start(@drawer)

    post complete_stocktake_path(stocktake), params: { zero_uncounted: "true" }
    assert_equal 0, quantity(@resistor, @drawer)
    assert_equal 0, quantity(@cap, @drawer)
  end

  test "complete reports a refused adjustment and changes nothing" do
    stocktake = start(@drawer)
    stocktake.count!(line(stocktake, @resistor, @drawer), 0, user: @user)
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -40)

    assert_no_difference -> { StockMovement.count } do
      post complete_stocktake_path(stocktake)
    end
    assert_match(/Nothing was adjusted \(Resistor 10k in Drawer 1: .*negative stock/, flash[:alert])
    assert stocktake.reload.in_progress?
  end

  test "a completed stocktake can't be completed, counted or discarded" do
    stocktake = start(@drawer)
    stocktake.complete!(user: @user)

    post complete_stocktake_path(stocktake)
    assert_match(/already completed/, flash[:alert])

    patch stocktake_stocktake_line_path(stocktake, line(stocktake, @resistor, @drawer)), params: { stocktake_line: { counted_quantity: "3" } }
    assert_match(/already completed/, flash[:alert])

    post scan_stocktake_path(stocktake), params: { code: "R-10K", increment: "true" }
    assert_match(/already completed/, flash[:alert])

    assert_no_difference -> { Stocktake.count } do
      delete stocktake_path(stocktake)
    end
    assert_match(/kept with the adjustments/, flash[:alert])
  end

  test "an in-progress stocktake can be discarded without touching stock" do
    stocktake = start(@cabinet)
    stocktake.count!(line(stocktake, @resistor, @drawer), 1, user: @user)

    assert_no_difference -> { StockMovement.count } do
      assert_difference -> { Stocktake.count } => -1, -> { StocktakeLine.count } => -3 do
        delete stocktake_path(stocktake)
      end
    end
    assert_redirected_to stocktakes_path
  end

  test "export downloads the count report as CSV" do
    @resistor.update!(name: "=HYPERLINK(\"x\")")
    stocktake = start(@cabinet)
    stocktake.count!(line(stocktake, @resistor, @drawer), 48, user: @user)

    get export_stocktake_path(stocktake)
    assert_response :success
    assert_equal "text/csv", response.media_type

    rows = CSV.parse(response.body, headers: true)
    resistor_row = rows.find { |row| row["IPN"] == "R-10K" }
    assert_equal "Cabinet > Drawer 1", resistor_row["Zone"]
    assert_equal "'=HYPERLINK(\"x\")", resistor_row["Name"]
    assert_equal [ "50", "48", "-2" ], resistor_row.values_at("Expected", "Counted", "Difference")
    assert_equal "-1.0", resistor_row["Value difference"]
  end

  test "viewers can read but not count" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    stocktake = start(@cabinet)
    resistor_line = line(stocktake, @resistor, @drawer)
    sign_in viewer
    post switch_organization_path(@org)

    get stocktake_path(stocktake)
    assert_response :success
    get export_stocktake_path(stocktake)
    assert_response :success

    assert_no_difference -> { Stocktake.count } do
      post stocktakes_path, params: { stocktake: { storage_location_id: @shelf.id } }
    end
    patch stocktake_stocktake_line_path(stocktake, resistor_line), params: { stocktake_line: { counted_quantity: "1" } }
    post stocktake_stocktake_lines_path(stocktake), params: { stocktake_line: { part_id: @resistor.id, storage_location_id: @cabinet.id } }
    post scan_stocktake_path(stocktake), params: { code: "R-10K", increment: "true" }
    assert_no_difference -> { StockMovement.count } do
      post complete_stocktake_path(stocktake)
    end
    assert_no_difference -> { Stocktake.count } do
      delete stocktake_path(stocktake)
    end

    assert_not resistor_line.reload.counted?
    assert_equal 3, stocktake.stocktake_lines.count
    assert stocktake.reload.in_progress?
    assert_match(/read-only/i, flash[:alert])
  end

  private

  def stock(part, location, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  def start(location, **attrs)
    stocktake = @org.stocktakes.new(storage_location: location, user: @user, **attrs)
    stocktake.save_with_generated_reference! { Stocktake.next_reference(@org) }
    stocktake.snapshot_stock!
    stocktake
  end

  def line(stocktake, part, location)
    stocktake.stocktake_lines.find_by!(part: part, storage_location: location)
  end

  def quantity(part, location)
    PartStorage.find_by(part: part, storage_location: location)&.quantity
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

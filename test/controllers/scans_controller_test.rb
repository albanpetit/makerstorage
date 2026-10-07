require "test_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get scan_path
    assert_redirected_to new_user_session_path
  end

  test "index without a code returns no result" do
    user = create_user

    sign_in user
    get scan_path
    assert_response :success

    assert_nil inertia_props["code"]
    assert_nil inertia_props["result"]
    assert_equal 0, inertia_props["today_count"]
    assert_empty inertia_props["recent_scans"]
  end

  test "index finds a part by barcode case-insensitively with locations sorted by quantity" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, name: "4.7k resistor", barcode: "QR-B2-T04", mpn: "R-0603-4K7")
    small = create_storage_location(organization: org, name: "Box A")
    big = create_storage_location(organization: org, name: "Box B")
    PartStorage.create!(part: part, storage_location: small, quantity: 5)
    PartStorage.create!(part: part, storage_location: big, quantity: 120)

    sign_in user
    get scan_path, params: { code: "qr-b2-t04" }
    assert_response :success

    result = inertia_props["result"]
    assert_equal "part", result["kind"]
    assert_equal "R-0603-4K7", result["part"]["reference"]
    assert_equal 125, result["part"]["total_quantity"]
    assert_equal [ "Box B", "Box A" ], result["part"]["locations"].map { |l| l["name"] }
    assert_equal [ 120, 5 ], result["part"]["locations"].map { |l| l["quantity"] }
  end

  test "index finds a part by sku or mpn" do
    user = create_user
    org = user.organizations.first
    create_part(organization: org, sku: "SKU-042", mpn: "IC-ATMEGA328")

    sign_in user
    get scan_path, params: { code: "SKU-042" }
    assert_equal "part", inertia_props["result"]["kind"]

    get scan_path, params: { code: "ic-atmega328" }
    assert_equal "part", inertia_props["result"]["kind"]
  end

  test "index offers every organization zone when the part has no storage yet" do
    user = create_user
    org = user.organizations.first
    create_part(organization: org, barcode: "NEW-PART")
    create_storage_location(organization: org, name: "Shelf 1")
    create_storage_location(organization: org, name: "Shelf 2")

    sign_in user
    get scan_path, params: { code: "NEW-PART" }

    locations = inertia_props["result"]["part"]["locations"]
    assert_equal [ "Shelf 1", "Shelf 2" ], locations.map { |l| l["name"] }
    assert_equal [ 0, 0 ], locations.map { |l| l["quantity"] }
  end

  test "index finds a storage zone by code with its stock summary" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Lab", location_type: "room")
    box = create_storage_location(organization: org, name: "Box B2-T04", location_type: "box", parent: room, code: "Z-B2-T04")
    create_storage_location(organization: org, parent: box)
    part = create_part(organization: org)
    PartStorage.create!(part: part, storage_location: box, quantity: 40)

    sign_in user
    get scan_path, params: { code: "z-b2-t04" }
    assert_response :success

    result = inertia_props["result"]
    assert_equal "location", result["kind"]
    assert_equal "Box B2-T04", result["location"]["name"]
    assert_equal "Lab > Box B2-T04", result["location"]["full_path"]
    assert_equal 1, result["location"]["parts_count"]
    assert_equal 40, result["location"]["total_quantity"]
    assert_equal 1, result["location"]["children_count"]
  end

  test "index returns unknown for a code that matches nothing" do
    user = create_user

    sign_in user
    get scan_path, params: { code: "NOPE-123" }
    assert_response :success
    assert_equal "unknown", inertia_props["result"]["kind"]
  end

  test "index does not match another organization's part or zone codes" do
    user = create_user
    other_org = create_organization
    create_part(organization: other_org, barcode: "FOREIGN-PART")
    create_storage_location(organization: other_org, code: "FOREIGN-ZONE")

    sign_in user
    get scan_path, params: { code: "FOREIGN-PART" }
    assert_equal "unknown", inertia_props["result"]["kind"]

    get scan_path, params: { code: "FOREIGN-ZONE" }
    assert_equal "unknown", inertia_props["result"]["kind"]
  end

  test "index lists only scanner movements in recent scans and counts today's" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, mpn: "IC-NE555")
    location = create_storage_location(organization: org, name: "Drawer A1")

    scanner = StockMovement.create!(organization: org, part: part, storage_location: location, user: user,
                                    movement_type: "in", quantity_delta: 10, reason: ScansController::SCANNER_REASON)
    StockMovement.create!(organization: org, part: part, storage_location: location, user: user,
                          movement_type: "in", quantity_delta: 5, reason: "Restock")
    old = StockMovement.create!(organization: org, part: part, storage_location: location, user: user,
                                movement_type: "in", quantity_delta: 3, reason: ScansController::SCANNER_REASON,
                                created_at: 2.days.ago)

    sign_in user
    get scan_path
    assert_response :success

    recent = inertia_props["recent_scans"]
    assert_equal [ scanner.id, old.id ], recent.map { |scan| scan["id"] }
    assert_equal "IC-NE555", recent.first["reference"]
    assert_equal "Drawer A1", recent.first["location_name"]
    assert_equal 10, recent.first["quantity_delta"]
    assert_equal 1, inertia_props["today_count"]
  end

  test "create_movement records an inbound scanner count for a positive delta" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      post scan_movements_path, params: {
        scan: { part_id: part.id, storage_location_id: location.id, quantity_delta: 7 }
      }
    end

    assert_redirected_to scan_path
    movement = StockMovement.last
    assert_equal "in", movement.movement_type
    assert_equal 7, movement.quantity_delta
    assert_equal ScansController::SCANNER_REASON, movement.reason
    assert_equal user, movement.user
    assert_equal 7, PartStorage.find_by(part: part, storage_location: location).quantity
  end

  test "create_movement records an outbound scanner count for a negative delta" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 10)

    sign_in user
    post scan_movements_path, params: {
      scan: { part_id: part.id, storage_location_id: location.id, quantity_delta: -4 }
    }

    movement = StockMovement.last
    assert_equal "out", movement.movement_type
    assert_equal(-4, movement.quantity_delta)
    assert_equal 6, PartStorage.find_by(part: part, storage_location: location).quantity
  end

  test "create_movement rejects an overdraw when negative stock is not allowed" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 3)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post scan_movements_path, params: {
        scan: { part_id: part.id, storage_location_id: location.id, quantity_delta: -10 }
      }
    end

    assert_redirected_to scan_path
    assert_equal "Failed to record movement.", flash[:alert]
    assert_equal 3, PartStorage.find_by(part: part, storage_location: location).quantity
  end

  test "create_movement returns not found for another organization's part" do
    user = create_user
    org = user.organizations.first
    other_org = create_organization
    other_part = create_part(organization: other_org)
    location = create_storage_location(organization: org)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post scan_movements_path, params: {
        scan: { part_id: other_part.id, storage_location_id: location.id, quantity_delta: 5 }
      }
    end
    assert_response :not_found
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

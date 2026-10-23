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

  test "index gives each zone of the scanned part its code and type for the zone picker" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, barcode: "STORED")
    box = create_storage_location(organization: org, name: "Box A", location_type: "box", code: "BA")
    PartStorage.create!(part: part, storage_location: box, quantity: 7)

    sign_in user
    get scan_path, params: { code: "STORED" }

    location = inertia_props["result"]["part"]["locations"].sole
    assert_equal({ "id" => box.id, "name" => "Box A", "code" => "BA", "location_type" => "box", "quantity" => 7 }, location)
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

  test "index points a scanned zone at the stocktake already counting it" do
    user = create_user
    org = user.organizations.first
    cabinet = create_storage_location(organization: org, name: "Cabinet", code: "CAB")
    drawer = create_storage_location(organization: org, name: "Drawer", code: "DR", parent: cabinet)
    other = create_storage_location(organization: org, name: "Shelf", code: "SH")
    stocktake = org.stocktakes.create!(storage_location: cabinet, reference: "ST-1")
    org.stocktakes.create!(storage_location: other, reference: "ST-0", status: "completed")

    sign_in user
    get scan_path(code: "DR")
    assert_equal({ "id" => stocktake.id, "reference" => "ST-1" }, inertia_props["result"]["location"]["stocktake"])

    get scan_path(code: "SH")
    assert_nil inertia_props["result"]["location"]["stocktake"]
  end

  test "index finds a part by IPN before a part whose MPN matches it" do
    user = create_user
    org = user.organizations.first
    create_part(organization: org, name: "Decoy", mpn: "MS-00042")
    part = create_part(organization: org, name: "Labelled", ipn: "MS-00042")

    sign_in user
    get scan_path, params: { code: "ms-00042" }

    assert_equal "part", inertia_props["result"]["kind"]
    assert_equal part.id, inertia_props["result"]["part"]["id"]
  end

  test "index resolves label fallback codes for parts and zones" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, name: "No identifiers")
    zone = create_storage_location(organization: org, name: "Drawer 7")

    sign_in user
    get scan_path, params: { code: "part:#{part.id}" }
    assert_equal part.id, inertia_props["result"]["part"]["id"]

    get scan_path, params: { code: "ZONE:#{zone.id}" }
    assert_equal "location", inertia_props["result"]["kind"]
    assert_equal zone.id, inertia_props["result"]["location"]["id"]
  end

  test "index keeps only the code of a scanned label link, whatever its host" do
    user = create_user
    org = user.organizations.first
    zone = create_storage_location(organization: org, code: "Z-A1")

    sign_in user
    get scan_path, params: { code: "http://192.168.1.20:3000/scan?code=Z-A1" }
    assert_equal "Z-A1", inertia_props["code"]
    assert_equal zone.id, inertia_props["result"]["location"]["id"]

    get scan_path, params: { code: "https://example.test/scan/?code=zone%3A#{zone.id}" }
    assert_equal zone.id, inertia_props["result"]["location"]["id"]
  end

  test "index treats other links as plain codes" do
    user = create_user

    sign_in user
    get scan_path, params: { code: "https://example.test/parts?code=Z-A1" }
    assert_equal "https://example.test/parts?code=Z-A1", inertia_props["code"]
    assert_equal "unknown", inertia_props["result"]["kind"]
  end

  test "index does not resolve another organization's records by fallback code" do
    user = create_user
    other_org = create_organization
    part = create_part(organization: other_org)
    zone = create_storage_location(organization: other_org)

    sign_in user
    get scan_path, params: { code: "part:#{part.id}" }
    assert_equal "unknown", inertia_props["result"]["kind"]

    get scan_path, params: { code: "zone:#{zone.id}" }
    assert_equal "unknown", inertia_props["result"]["kind"]

    get scan_path, params: { code: "part:#{part.id}", zone: zone.id }
    assert_nil inertia_props["preferred_location_id"]
  end

  test "index lists a scanned zone's stocked parts, largest first" do
    user = create_user
    org = user.organizations.first
    drawer = create_storage_location(organization: org, code: "D-1")
    few = create_part(organization: org, name: "Few", mpn: "FEW-1")
    many = create_part(organization: org, name: "Many", mpn: "MANY-1")
    empty = create_part(organization: org, name: "Empty")
    PartStorage.create!(part: few, storage_location: drawer, quantity: 3)
    PartStorage.create!(part: many, storage_location: drawer, quantity: 90)
    PartStorage.create!(part: empty, storage_location: drawer, quantity: 0)

    sign_in user
    get scan_path, params: { code: "D-1" }

    contents = inertia_props["result"]["location"]["contents"]
    assert_equal [ many.id, few.id ], contents.map { |c| c["id"] }
    assert_equal [ "MANY-1", "FEW-1" ], contents.map { |c| c["reference"] }
    assert_equal [ 90, 3 ], contents.map { |c| c["quantity"] }
  end

  test "index passes the zone a part was opened from" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    zone = create_storage_location(organization: org)

    sign_in user
    get scan_path, params: { code: "part:#{part.id}", zone: zone.id }
    assert_equal zone.id, inertia_props["preferred_location_id"]

    get scan_path, params: { code: "part:#{part.id}" }
    assert_nil inertia_props["preferred_location_id"]
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

  test "today's scan count follows the organization's time zone" do
    user = create_user
    org = user.organizations.first
    org.update!(timezone: "Pacific/Auckland")
    part = create_part(organization: org)
    location = create_storage_location(organization: org)

    travel_to Time.utc(2026, 10, 8, 20, 0) do # already Oct 9, 09:00 in Auckland
      # 10:00 UTC Oct 8 is Oct 8 in Auckland (yesterday there); 12:00 UTC is Oct 9.
      [ Time.utc(2026, 10, 8, 10, 0), Time.utc(2026, 10, 8, 12, 0) ].each do |at|
        StockMovement.create!(organization: org, part: part, storage_location: location, user: user,
                              movement_type: "in", quantity_delta: 1, reason: ScansController::SCANNER_REASON, created_at: at)
      end

      sign_in user
      get scan_path
      assert_equal 1, inertia_props["today_count"]
    end
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

  test "index matches a supplier bag label by the supplier part number" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org, name: "DigiKey")
    part = create_part(organization: org, mpn: "SN74HC595N-OTHER")
    PartSupplier.create!(part: part, supplier: supplier, supplier_sku: "296-1395-5-ND")
    create_part(organization: org, mpn: "SN74HC595N")

    sign_in user
    get scan_path, params: { code: digikey_label }
    assert_response :success

    result = inertia_props["result"]
    assert_equal "supplier_label", result["kind"]
    assert_equal part.id, result["part"]["id"]
    assert_equal "SN74HC595N", result["label"]["mpn"]
    assert_equal 25, result["label"]["quantity"]
    assert_equal "DigiKey 84512345", result["reference"]
    assert_nil result["previous_receipt"]
    assert_empty result["open_orders"]
  end

  test "index matches a supplier bag label by customer part number, then sku, then mpn" do
    user = create_user
    org = user.organizations.first
    by_mpn = create_part(organization: org, mpn: "SN74HC595N")

    sign_in user
    get scan_path, params: { code: digikey_label }
    assert_equal by_mpn.id, inertia_props["result"]["part"]["id"]

    by_sku = create_part(organization: org, sku: "296-1395-5-nd")
    get scan_path, params: { code: digikey_label }
    assert_equal by_sku.id, inertia_props["result"]["part"]["id"]

    by_ipn = create_part(organization: org, ipn: "MS-00042")
    get scan_path, params: { code: digikey_label(customer: "MS-00042") }
    assert_equal by_ipn.id, inertia_props["result"]["part"]["id"]
  end

  test "index returns an unmatched supplier label so the part can be created" do
    user = create_user
    org = user.organizations.first
    other_org = create_organization
    create_part(organization: other_org, mpn: "SN74HC595N")
    create_part(organization: org, name: "Unrelated")

    sign_in user
    get scan_path, params: { code: digikey_label }

    result = inertia_props["result"]
    assert_equal "supplier_label", result["kind"]
    assert_nil result["part"]
    assert_equal "296-1395-5-ND", result["label"]["supplier_sku"]
  end

  test "index flags a supplier bag that was already received and the part's open orders" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, mpn: "SN74HC595N")
    location = create_storage_location(organization: org, name: "Drawer A1")
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in",
      quantity_delta: 25, reason: ScansController::LABEL_REASON, reference: "DigiKey 84512345")
    order = create_order(organization: org, reference: "PO-1")
    order.order_lines.create!(part: part, quantity: 25)
    received = create_order(organization: org, reference: "PO-2")
    received.order_lines.create!(part: part, quantity: 5)
    received.update_column(:status, "cancelled")

    sign_in user
    get scan_path, params: { code: digikey_label }

    result = inertia_props["result"]
    assert_equal 25, result["previous_receipt"]["quantity"]
    assert_equal "Drawer A1", result["previous_receipt"]["location_name"]
    assert_equal [ { "id" => order.id, "reference" => "PO-1", "quantity" => 25 } ], result["open_orders"]

    get scan_path, params: { code: digikey_label(order: "99999") }
    assert_nil inertia_props["result"]["previous_receipt"]
  end

  test "receive credits a scanned bag to the chosen zone" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, mpn: "SN74HC595N")
    location = create_storage_location(organization: org, name: "Drawer A1")

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      post scan_receipts_path, params: {
        receipt: { part_id: part.id, storage_location_id: location.id, quantity: 25, reference: "DigiKey 84512345" }
      }
    end

    assert_redirected_to scan_path
    movement = StockMovement.last
    assert_equal "in", movement.movement_type
    assert_equal 25, movement.quantity_delta
    assert_equal ScansController::LABEL_REASON, movement.reason
    assert_equal "DigiKey 84512345", movement.reference
    assert_equal user, movement.user
    assert_equal 25, PartStorage.find_by(part: part, storage_location: location).quantity

    get scan_path
    assert_equal [ movement.id ], inertia_props["recent_scans"].map { |scan| scan["id"] }
    assert_equal 1, inertia_props["today_count"]
  end

  test "receive refuses a quantity that isn't positive" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)

    sign_in user
    [ 0, -5 ].each do |quantity|
      assert_no_difference -> { StockMovement.count } do
        post scan_receipts_path, params: {
          receipt: { part_id: part.id, storage_location_id: location.id, quantity: quantity }
        }
      end
      assert_equal "Failed to receive the bag.", flash[:alert]
    end
    assert_nil PartStorage.find_by(part: part, storage_location: location)
  end

  test "receive returns not found for another organization's part or zone" do
    user = create_user
    org = user.organizations.first
    other_org = create_organization
    part = create_part(organization: org)
    location = create_storage_location(organization: org)

    foreign_part = create_part(organization: other_org)
    foreign_zone = create_storage_location(organization: other_org)

    [ [ foreign_part, location ], [ part, foreign_zone ] ].each do |target_part, target_zone|
      sign_in user
      assert_no_difference -> { StockMovement.count } do
        post scan_receipts_path, params: {
          receipt: { part_id: target_part.id, storage_location_id: target_zone.id, quantity: 5 }
        }
      end
      assert_response :not_found
    end
  end

  test "viewers cannot receive a bag" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)
    viewer = create_user
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")

    sign_in viewer
    post "/organizations/#{org.id}/switch"
    assert_no_difference -> { StockMovement.count } do
      post scan_receipts_path, params: {
        receipt: { part_id: part.id, storage_location_id: location.id, quantity: 5 }
      }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "offline returns the organization's snapshot with a CSRF token, viewers included" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, ipn: "MS-00001")
    create_part(organization: create_organization, ipn: "OTHER")
    viewer = create_user
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")

    sign_in user
    get scan_offline_path
    assert_response :success
    json = response.parsed_body
    assert_equal org.id, json["organization_id"]
    assert_equal [ part.id ], json["parts"].map { |row| row["id"] }
    assert json["csrf_token"].present?

    sign_in viewer
    post "/organizations/#{org.id}/switch"
    get scan_offline_path
    assert_response :success
    assert_equal org.id, response.parsed_body["organization_id"]
  end

  test "offline answers 401 to a signed-out visitor" do
    get scan_offline_path
    assert_response :unauthorized
  end

  test "sync writes queued scans once and reports each" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    location = create_storage_location(organization: org)
    operation = { id: SecureRandom.uuid, kind: "count", part_id: part.id, storage_location_id: location.id, quantity: 4, scanned_at: 1.hour.ago.iso8601 }

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      post scan_sync_path, params: { organization_id: org.id, operations: [ operation ] }, as: :json
    end
    assert_response :success
    assert_equal [ { "id" => operation[:id], "status" => "saved" } ], response.parsed_body["results"]
    assert_equal 4, PartStorage.find_by!(part: part, storage_location: location).quantity

    assert_no_difference -> { StockMovement.count } do
      post scan_sync_path, params: { organization_id: org.id, operations: [ operation ] }, as: :json
    end
    assert_equal "duplicate", response.parsed_body["results"].first["status"]
  end

  test "sync refuses scans queued in another organization" do
    user = create_user
    org = user.organizations.first

    sign_in user
    post scan_sync_path, params: { organization_id: org.id + 1000, operations: [] }, as: :json
    assert_response :conflict
  end

  test "viewers cannot sync scans" do
    owner = create_user
    org = owner.organizations.first
    viewer = create_user
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")
    part = create_part(organization: org)
    location = create_storage_location(organization: org)

    sign_in viewer
    post "/organizations/#{org.id}/switch"
    assert_no_difference -> { StockMovement.count } do
      post scan_sync_path, params: { organization_id: org.id, operations: [ { id: "a1", kind: "count", part_id: part.id, storage_location_id: location.id, quantity: 1 } ] }, as: :json
    end
    assert_response :forbidden
  end

  private

  def digikey_label(customer: "296-1395-5-ND", order: "84512345")
    gs = SupplierLabel::GS
    rs = SupplierLabel::RS
    fields = [ "P#{customer}", "1PSN74HC595N", "K", "1K#{order}", "Q25", "12Z4389236" ]
    fields.insert(1, "30P296-1395-5-ND") unless customer.end_with?("-ND")
    "[)>#{rs}06#{gs}#{fields.join(gs)}#{rs}#{SupplierLabel::EOT}"
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

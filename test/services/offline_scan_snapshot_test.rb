require "test_helper"

class OfflineScanSnapshotTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @room = create_storage_location(organization: @org, name: "Room", code: "R1")
    @drawer = create_storage_location(organization: @org, name: "Drawer", location_type: "drawer", parent: @room, code: "D1")
  end

  test "lists parts with the codes the scanner matches and their stock per zone" do
    category = create_category(organization: @org, name: "Logic", color: "#ff0000")
    part = create_part(organization: @org, name: "Shift register", category: category, ipn: "MS-00042", barcode: "BC-1",
      sku: "SKU-1", mpn: "SN74HC595N", min_stock_threshold: 10)
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: part, supplier: supplier, supplier_sku: "296-1395-5-ND")
    StockMovement.create!(organization: @org, part: part, storage_location: @drawer, movement_type: "in", quantity_delta: 7)
    empty = create_part(organization: @org, name: "Never stocked")

    json = OfflineScanSnapshot.new(@org).as_json
    snapshot_part = json[:parts].find { |row| row[:id] == part.id }

    assert_equal @org.id, json[:organization_id]
    assert_equal "SN74HC595N", snapshot_part[:reference]
    assert_equal %w[MS-00042 BC-1 SKU-1 SN74HC595N], snapshot_part.values_at(:ipn, :barcode, :sku, :mpn)
    assert_equal [ "296-1395-5-ND" ], snapshot_part[:supplier_skus]
    assert_equal({ name: "Logic", color: "#ff0000" }, snapshot_part[:category])
    assert_equal 10, snapshot_part[:min_stock_threshold]
    assert_equal [ [ @drawer.id, 7 ] ], snapshot_part[:stock]
    assert_equal [], json[:parts].find { |row| row[:id] == empty.id }[:stock]
  end

  test "lists zones with their full path and code" do
    zone = OfflineScanSnapshot.new(@org).as_json[:locations].find { |row| row[:id] == @drawer.id }

    assert_equal "Room > Drawer", zone[:full_path]
    assert_equal "D1", zone[:code]
    assert_equal @room.id, zone[:parent_id]
  end

  test "lists open order lines and recent bag receipts" do
    part = create_part(organization: @org)
    open_order = create_order(organization: @org)
    open_order.order_lines.create!(part: part, quantity: 30, unit_price: 0.1)
    received = create_order(organization: @org)
    received.order_lines.create!(part: part, quantity: 5, unit_price: 0.1)
    received.update_columns(status: "received")
    StockMovement.create!(organization: @org, part: part, storage_location: @drawer, movement_type: "in", quantity_delta: 25,
      reason: ScansController::LABEL_REASON, reference: "DigiKey 845")

    json = OfflineScanSnapshot.new(@org).as_json

    assert_equal [ { part_id: part.id, id: open_order.id, reference: open_order.reference, quantity: 30 } ], json[:open_orders]
    assert_equal [ [ part.id, "DigiKey 845", 25, "Drawer" ] ], json[:label_receipts].map { |row| row.values_at(:part_id, :reference, :quantity, :location_name) }
  end

  test "leaves out other organizations' data" do
    other = create_organization
    create_part(organization: other, ipn: "OTHER")
    create_storage_location(organization: other, code: "OTHER")

    json = OfflineScanSnapshot.new(@org).as_json

    assert_empty json[:parts]
    assert_equal [ @room.id, @drawer.id ].sort, json[:locations].map { |row| row[:id] }.sort
  end
end

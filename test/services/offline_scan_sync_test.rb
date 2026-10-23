require "test_helper"

class OfflineScanSyncTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @part = create_part(organization: @org, mpn: "SN74HC595N")
    @drawer = create_storage_location(organization: @org, name: "Drawer")
    StockMovement.create!(organization: @org, part: @part, storage_location: @drawer, movement_type: "in", quantity_delta: 10)
  end

  def operation(**attrs)
    { "id" => SecureRandom.uuid, "kind" => "count", "part_id" => @part.id, "storage_location_id" => @drawer.id,
      "quantity" => -3, "scanned_at" => 1.hour.ago.iso8601 }.merge(attrs.stringify_keys)
  end

  def sync(*operations)
    OfflineScanSync.new(@org, @user).call(operations)
  end

  def stock
    PartStorage.find_by!(part: @part, storage_location: @drawer).quantity
  end

  test "writes a count as the scanner page would, stamped with the scan" do
    scanned_at = 2.hours.ago.change(usec: 0)
    op = operation(scanned_at: scanned_at.iso8601)

    assert_equal [ { id: op["id"], status: "saved" } ], sync(op)

    movement = @org.stock_movements.find_by!(offline_uuid: op["id"])
    assert_equal "out", movement.movement_type
    assert_equal(-3, movement.quantity_delta)
    assert_equal ScansController::SCANNER_REASON, movement.reason
    assert_equal @user, movement.user
    assert_equal scanned_at, movement.scanned_at
    assert_equal 7, stock
  end

  test "writes a bag receipt with its reference" do
    op = operation(kind: "receipt", quantity: 25, reference: "DigiKey 845")

    sync(op)

    movement = @org.stock_movements.find_by!(offline_uuid: op["id"])
    assert_equal "in", movement.movement_type
    assert_equal ScansController::LABEL_REASON, movement.reason
    assert_equal "DigiKey 845", movement.reference
    assert_equal 35, stock
  end

  test "never writes the same scan twice" do
    op = operation

    sync(op)
    assert_no_difference -> { StockMovement.count } do
      assert_equal "duplicate", sync(op).first[:status]
    end
    assert_equal 7, stock
  end

  test "reports a scan the ledger refuses without holding up the others" do
    too_many = operation(quantity: -50)
    fine = operation(quantity: 2)

    results = sync(too_many, fine)

    assert_equal %w[rejected saved], results.map { |result| result[:status] }
    assert results.first[:error].present?
    assert_equal 12, stock
  end

  test "refuses unknown kinds, bad ids, and parts or zones of another organization" do
    other_part = create_part(organization: create_organization)

    results = sync(operation(kind: "teleport"), operation(id: "x" * 65), operation(id: "bad id!"), operation(part_id: other_part.id), operation(storage_location_id: 0))

    assert_equal %w[rejected] * 5, results.map { |result| result[:status] }
    assert_equal I18n.t("errors.offline_scan.not_found"), results.last[:error]
    assert_equal 10, stock
  end

  test "ignores a scan time in the future or unreadable" do
    future = operation(scanned_at: 1.day.from_now.iso8601)
    garbage = operation(scanned_at: "yesterday-ish")

    sync(future, garbage)

    assert_nil @org.stock_movements.find_by!(offline_uuid: future["id"]).scanned_at
    assert_nil @org.stock_movements.find_by!(offline_uuid: garbage["id"]).scanned_at
  end

  test "the same scan id can exist in two organizations" do
    other_user = create_user
    other_org = other_user.organizations.first
    other_part = create_part(organization: other_org)
    other_zone = create_storage_location(organization: other_org)
    op = operation(quantity: 1)

    sync(op)
    result = OfflineScanSync.new(other_org, other_user).call([ op.merge("part_id" => other_part.id, "storage_location_id" => other_zone.id) ])

    assert_equal "saved", result.first[:status]
  end
end

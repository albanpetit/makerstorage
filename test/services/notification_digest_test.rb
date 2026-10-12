require "test_helper"

class NotificationDigestTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @location = create_storage_location(organization: @org)
    @date = Date.new(2026, 10, 12)
  end

  test "lists parts below their threshold, emptiest first" do
    low = create_part(organization: @org, name: "Low", min_stock_threshold: 10)
    PartStorage.create!(part: low, storage_location: @location, quantity: 8)
    empty = create_part(organization: @org, name: "Empty", min_stock_threshold: 10)
    healthy = create_part(organization: @org, name: "Healthy", min_stock_threshold: 10)
    PartStorage.create!(part: healthy, storage_location: @location, quantity: 50)

    items = NotificationDigest.new(@org, date: @date).low_stock

    assert_equal [ empty.id, low.id ], items.map(&:part_id)
    assert_equal [ 0, 8 ], items.map(&:quantity)
    assert_equal 10, items.first.threshold
  end

  test "lists open orders past their expected delivery" do
    late = create_order(organization: @org, status: "shipped", expected_delivery: @date - 3)
    create_order(organization: @org, status: "pending", expected_delivery: @date)
    create_order(organization: @org, status: "pending")
    create_order(organization: @org, status: "cancelled", expected_delivery: @date - 10)

    items = NotificationDigest.new(@org, date: @date).late_orders

    assert_equal [ late.id ], items.map(&:order_id)
    assert_equal 3, items.first.days_late
    assert_equal late.supplier.name, items.first.supplier_name
  end

  test "leaves out the alert types switched off" do
    create_part(organization: @org, min_stock_threshold: 10)
    create_order(organization: @org, status: "pending", expected_delivery: @date - 1)
    @org.update_columns(notify_low_stock: false, notify_late_orders: false)

    digest = NotificationDigest.new(@org, date: @date)

    assert_empty digest.low_stock
    assert_empty digest.late_orders
    assert digest.empty?
  end

  test "never reports another organization's data" do
    other = create_organization
    create_part(organization: other, min_stock_threshold: 10)
    create_order(organization: other, status: "pending", expected_delivery: @date - 1)

    assert NotificationDigest.new(@org, date: @date).empty?
  end
end

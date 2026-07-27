require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @supplier = create_supplier(organization: @org)
  end

  test "valid with organization, supplier, and a default status" do
    order = Order.new(organization: @org, supplier: @supplier)
    assert order.valid?
    assert_equal "pending", order.status
  end

  test "rejects a status outside the allowed list" do
    order = Order.new(organization: @org, supplier: @supplier, status: "shipping")
    assert_not order.valid?
    assert_includes order.errors[:status], "is not included in the list"
  end

  test "rejects a negative total_amount" do
    order = Order.new(organization: @org, supplier: @supplier, total_amount: -1)
    assert_not order.valid?
    assert_includes order.errors[:total_amount], "must be greater than or equal to 0"
  end

  test "supplier must belong to the same organization" do
    other_org = create_organization
    foreign_supplier = create_supplier(organization: other_org)
    order = Order.new(organization: @org, supplier: foreign_supplier)
    assert_not order.valid?
    assert_includes order.errors[:supplier], "must belong to the same organization"
  end

  test "reference must be unique within an organization" do
    Order.create!(organization: @org, supplier: @supplier, reference: "PO-1")
    duplicate = Order.new(organization: @org, supplier: @supplier, reference: "PO-1")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:reference], "has already been taken"
  end

  test "next_reference appends a suffix on same-supplier same-day collision" do
    date = Date.new(2026, 7, 14)
    first = Order.next_reference(@org, @supplier, date: date)
    assert_equal "PO-20260714-#{@supplier.id}", first
    Order.create!(organization: @org, supplier: @supplier, reference: first)

    second = Order.next_reference(@org, @supplier, date: date)
    assert_equal "PO-20260714-#{@supplier.id}-2", second
  end

  test "status predicate methods" do
    order = Order.create!(organization: @org, supplier: @supplier, status: "shipped")
    assert order.shipped?
    assert_not order.pending?
    assert_not order.received?
    assert_not order.cancelled?
  end

  test "computed_total sums quantity times unit_price across lines" do
    order = Order.create!(organization: @org, supplier: @supplier)
    category = create_category(organization: @org)
    part_a = create_part(organization: @org, category: category)
    part_b = create_part(organization: @org, category: category)
    OrderLine.create!(order: order, part: part_a, quantity: 10, unit_price: 1.5)
    OrderLine.create!(order: order, part: part_b, quantity: 4, unit_price: 2.0)

    assert_equal 23.0, order.computed_total.to_f
  end

  test "of_status, pending, and received scopes" do
    pending = Order.create!(organization: @org, supplier: @supplier, status: "pending")
    received = Order.create!(organization: @org, supplier: @supplier, status: "received")

    assert_equal [ pending ], Order.pending.to_a
    assert_equal [ received ], Order.received.to_a
    assert_equal [ received ], Order.of_status("received").to_a
  end

  test "editable? only while pending or shipped" do
    assert Order.new(status: "pending").editable?
    assert Order.new(status: "shipped").editable?
    assert_not Order.new(status: "received").editable?
    assert_not Order.new(status: "cancelled").editable?
  end

  test "recalculate_total! syncs total_amount to the sum of lines" do
    order = Order.create!(organization: @org, supplier: @supplier)
    category = create_category(organization: @org)
    part = create_part(organization: @org, category: category)
    OrderLine.create!(order: order, part: part, quantity: 3, unit_price: 2.0)

    order.recalculate_total!
    assert_equal 6.0, order.reload.total_amount.to_f
  end

  test "advance! steps pending -> shipped -> received and stops at the end" do
    order = Order.create!(organization: @org, supplier: @supplier, status: "pending")

    first = order.advance!(user: nil)
    assert first.advanced
    assert_equal "shipped", first.status
    assert_equal "shipped", order.reload.status

    second = order.advance!(user: create_user)
    assert_equal "received", second.status

    third = order.advance!(user: nil)
    assert_not third.advanced
  end

  test "advance! to received credits stock into each line's first location" do
    user = create_user
    category = create_category(organization: @org)
    location = create_storage_location(organization: @org)
    part = create_part(organization: @org, category: category)
    part.part_storages.create!(storage_location: location, quantity: 0)

    order = Order.create!(organization: @org, supplier: @supplier, status: "shipped")
    OrderLine.create!(order: order, part: part, quantity: 25, unit_price: 1.0)

    assert_difference -> { StockMovement.count } => 1 do
      result = order.advance!(user: user)
      assert_empty result.skipped
    end
    assert_equal 25, part.reload.total_quantity
  end

  test "advance! to received splits a line's allocations across zones" do
    user = create_user
    category = create_category(organization: @org)
    drawer_a = create_storage_location(organization: @org, name: "Drawer A")
    drawer_b = create_storage_location(organization: @org, name: "Drawer B")
    part = create_part(organization: @org, category: category)

    order = Order.create!(organization: @org, supplier: @supplier, status: "shipped")
    line = OrderLine.create!(order: order, part: part, quantity: 100, unit_price: 0.01)
    line.allocations.create!(storage_location: drawer_a, quantity: 60)
    line.allocations.create!(storage_location: drawer_b, quantity: 40)

    assert_difference -> { StockMovement.count } => 2 do
      result = order.advance!(user: user)
      assert_empty result.skipped
    end

    assert_equal 60, PartStorage.find_by(part: part, storage_location: drawer_a).quantity
    assert_equal 40, PartStorage.find_by(part: part, storage_location: drawer_b).quantity
    assert_equal 100, part.reload.total_quantity
  end

  test "advance! reports lines whose part has no storage location as skipped" do
    user = create_user
    category = create_category(organization: @org)
    part = create_part(organization: @org, category: category)

    order = Order.create!(organization: @org, supplier: @supplier, status: "shipped")
    OrderLine.create!(order: order, part: part, quantity: 10)

    assert_no_difference -> { StockMovement.count } do
      result = order.advance!(user: user)
      assert_equal [ part.reference ], result.skipped
    end
    assert_equal "received", order.reload.status
  end
end

require "test_helper"

class OrderLineTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @supplier = create_supplier(organization: @org)
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @order = Order.create!(organization: @org, supplier: @supplier)
  end

  test "valid with an order, part, and positive quantity" do
    line = OrderLine.new(order: @order, part: @part, quantity: 5, unit_price: 1.25)
    assert line.valid?
  end

  test "rejects a zero or negative quantity" do
    line = OrderLine.new(order: @order, part: @part, quantity: 0, unit_price: 1)
    assert_not line.valid?
    assert_includes line.errors[:quantity], "must be greater than 0"

    line.quantity = -1
    assert_not line.valid?
  end

  test "rejects a negative unit_price" do
    line = OrderLine.new(order: @order, part: @part, quantity: 1, unit_price: -0.01)
    assert_not line.valid?
    assert_includes line.errors[:unit_price], "must be greater than or equal to 0"
  end

  test "unit_price is optional" do
    line = OrderLine.new(order: @order, part: @part, quantity: 1, unit_price: nil)
    assert line.valid?
  end

  test "subtotal multiplies quantity by unit_price" do
    line = OrderLine.create!(order: @order, part: @part, quantity: 4, unit_price: 2.5)
    assert_equal 10.0, line.subtotal.to_f
  end

  test "subtotal is nil without a unit_price" do
    line = OrderLine.create!(order: @order, part: @part, quantity: 4, unit_price: nil)
    assert_nil line.subtotal
  end

  test "allocated_quantity sums the allocations and fully_allocated? checks the total" do
    location_a = create_storage_location(organization: @org)
    location_b = create_storage_location(organization: @org)
    line = OrderLine.create!(order: @order, part: @part, quantity: 10)

    assert_equal 0, line.allocated_quantity
    assert_not line.fully_allocated?

    line.allocations.create!(storage_location: location_a, quantity: 4)
    assert_not line.fully_allocated?

    line.allocations.create!(storage_location: location_b, quantity: 6)
    assert_equal 10, line.allocated_quantity
    assert line.fully_allocated?
  end

  test "changing the quantity drops a split sized for the old quantity" do
    org = create_organization
    line = create_order(organization: org, reference: "PO-1").order_lines.create!(part: create_part(organization: org), quantity: 10)
    line.allocations.create!(storage_location: create_storage_location(organization: org), quantity: 10)

    line.update!(unit_price: 1.5)
    assert_equal 1, line.allocations.count, "a price-only edit keeps the split"

    line.update!(quantity: 15)
    assert_equal 0, line.allocations.count
  end
end

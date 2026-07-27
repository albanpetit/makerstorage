require "test_helper"

class OrderLineAllocationTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @supplier = create_supplier(organization: @org)
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @location = create_storage_location(organization: @org)
    @order = create_order(organization: @org, supplier: @supplier)
    @line = @order.order_lines.create!(part: @part, quantity: 10)
  end

  test "valid with a positive quantity and same-org zone" do
    allocation = OrderLineAllocation.new(order_line: @line, storage_location: @location, quantity: 5)
    assert allocation.valid?
  end

  test "rejects a zero or negative quantity" do
    allocation = OrderLineAllocation.new(order_line: @line, storage_location: @location, quantity: 0)
    assert_not allocation.valid?
    assert_includes allocation.errors[:quantity], "must be greater than 0"
  end

  test "storage location must belong to the part's organization" do
    other_org = create_organization
    foreign_location = create_storage_location(organization: other_org)
    allocation = OrderLineAllocation.new(order_line: @line, storage_location: foreign_location, quantity: 5)
    assert_not allocation.valid?
    assert_includes allocation.errors[:storage_location], "must belong to the same organization"
  end

  test "allocations are destroyed with their line" do
    @line.allocations.create!(storage_location: @location, quantity: 10)
    assert_difference -> { OrderLineAllocation.count } => -1 do
      @line.destroy
    end
  end
end

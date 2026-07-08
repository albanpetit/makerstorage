require "test_helper"

class PurchaseLineTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @supplier = create_supplier(organization: @org)
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @purchase = Purchase.create!(organization: @org, supplier: @supplier)
  end

  test "valid with a purchase, part, and positive quantity" do
    line = PurchaseLine.new(purchase: @purchase, part: @part, quantity: 5, unit_price: 1.25)
    assert line.valid?
  end

  test "rejects a zero or negative quantity" do
    line = PurchaseLine.new(purchase: @purchase, part: @part, quantity: 0, unit_price: 1)
    assert_not line.valid?
    assert_includes line.errors[:quantity], "must be greater than 0"

    line.quantity = -1
    assert_not line.valid?
  end

  test "rejects a negative unit_price" do
    line = PurchaseLine.new(purchase: @purchase, part: @part, quantity: 1, unit_price: -0.01)
    assert_not line.valid?
    assert_includes line.errors[:unit_price], "must be greater than or equal to 0"
  end

  test "unit_price is optional" do
    line = PurchaseLine.new(purchase: @purchase, part: @part, quantity: 1, unit_price: nil)
    assert line.valid?
  end

  test "subtotal multiplies quantity by unit_price" do
    line = PurchaseLine.create!(purchase: @purchase, part: @part, quantity: 4, unit_price: 2.5)
    assert_equal 10.0, line.subtotal.to_f
  end

  test "subtotal is nil without a unit_price" do
    line = PurchaseLine.create!(purchase: @purchase, part: @part, quantity: 4, unit_price: nil)
    assert_nil line.subtotal
  end
end

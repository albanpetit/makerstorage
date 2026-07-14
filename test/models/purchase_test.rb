require "test_helper"

class PurchaseTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @supplier = create_supplier(organization: @org)
  end

  test "valid with organization, supplier, and a default status" do
    purchase = Purchase.new(organization: @org, supplier: @supplier)
    assert purchase.valid?
    assert_equal "pending", purchase.status
  end

  test "rejects a status outside the allowed list" do
    purchase = Purchase.new(organization: @org, supplier: @supplier, status: "shipping")
    assert_not purchase.valid?
    assert_includes purchase.errors[:status], "is not included in the list"
  end

  test "rejects a negative total_amount" do
    purchase = Purchase.new(organization: @org, supplier: @supplier, total_amount: -1)
    assert_not purchase.valid?
    assert_includes purchase.errors[:total_amount], "must be greater than or equal to 0"
  end

  test "supplier must belong to the same organization" do
    other_org = create_organization
    foreign_supplier = create_supplier(organization: other_org)
    purchase = Purchase.new(organization: @org, supplier: foreign_supplier)
    assert_not purchase.valid?
    assert_includes purchase.errors[:supplier], "must belong to the same organization"
  end

  test "reference must be unique within an organization" do
    Purchase.create!(organization: @org, supplier: @supplier, reference: "PO-1")
    duplicate = Purchase.new(organization: @org, supplier: @supplier, reference: "PO-1")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:reference], "has already been taken"
  end

  test "next_reference appends a suffix on same-supplier same-day collision" do
    date = Date.new(2026, 7, 14)
    first = Purchase.next_reference(@org, @supplier, date: date)
    assert_equal "PO-20260714-#{@supplier.id}", first
    Purchase.create!(organization: @org, supplier: @supplier, reference: first)

    second = Purchase.next_reference(@org, @supplier, date: date)
    assert_equal "PO-20260714-#{@supplier.id}-2", second
  end

  test "status predicate methods" do
    purchase = Purchase.create!(organization: @org, supplier: @supplier, status: "shipped")
    assert purchase.shipped?
    assert_not purchase.pending?
    assert_not purchase.received?
    assert_not purchase.cancelled?
  end

  test "computed_total sums quantity times unit_price across lines" do
    purchase = Purchase.create!(organization: @org, supplier: @supplier)
    category = create_category(organization: @org)
    part_a = create_part(organization: @org, category: category)
    part_b = create_part(organization: @org, category: category)
    PurchaseLine.create!(purchase: purchase, part: part_a, quantity: 10, unit_price: 1.5)
    PurchaseLine.create!(purchase: purchase, part: part_b, quantity: 4, unit_price: 2.0)

    assert_equal 23.0, purchase.computed_total.to_f
  end

  test "of_status, pending, and received scopes" do
    pending = Purchase.create!(organization: @org, supplier: @supplier, status: "pending")
    received = Purchase.create!(organization: @org, supplier: @supplier, status: "received")

    assert_equal [ pending ], Purchase.pending.to_a
    assert_equal [ received ], Purchase.received.to_a
    assert_equal [ received ], Purchase.of_status("received").to_a
  end
end

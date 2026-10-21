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

  test "lists loans past their due date with what is still out" do
    part = create_part(organization: @org)
    PartStorage.create!(part: part, storage_location: @location, quantity: 5)
    late = lend(part, 3, due_on: @date - 2, borrower_name: "Alice")
    late.write_off!(line_id: late.loan_lines.first.id, quantity: 1)
    lend(part, 1, due_on: @date, borrower_name: "Bob")
    lend(part, 1, due_on: @date - 5, borrower_name: "Carol").return_all!(user: nil)

    items = NotificationDigest.new(@org, date: @date).overdue_loans

    assert_equal [ late.id ], items.map(&:loan_id)
    assert_equal [ "Alice", 2, 2 ], [ items.first.borrower_name, items.first.outstanding, items.first.days_late ]
  end

  test "leaves out the alert types switched off" do
    create_part(organization: @org, min_stock_threshold: 10)
    create_order(organization: @org, status: "pending", expected_delivery: @date - 1)
    part = create_part(organization: @org, min_stock_threshold: 0)
    PartStorage.create!(part: part, storage_location: @location, quantity: 1)
    lend(part, 1, due_on: @date - 1, borrower_name: "Alice")
    @org.update_columns(notify_low_stock: false, notify_late_orders: false, notify_overdue_loans: false)

    digest = NotificationDigest.new(@org, date: @date)

    assert_empty digest.low_stock
    assert_empty digest.late_orders
    assert_empty digest.overdue_loans
    assert digest.empty?
  end

  test "never reports another organization's data" do
    other = create_organization
    create_part(organization: other, min_stock_threshold: 10)
    create_order(organization: other, status: "pending", expected_delivery: @date - 1)

    assert NotificationDigest.new(@org, date: @date).empty?
  end

  private

  def lend(part, quantity, due_on:, borrower_name:)
    loan = @org.loans.new(borrower_name: borrower_name, due_on: due_on)
    loan.loan_lines.build(part: part, storage_location: @location, quantity: quantity)
    loan.lend!(user: nil)
  end
end

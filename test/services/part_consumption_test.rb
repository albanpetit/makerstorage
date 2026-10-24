require "test_helper"

class PartConsumptionTest < ActiveSupport::TestCase
  setup do
    @org = create_organization(timezone: "Etc/UTC", allow_negative_stock: true)
    @shelf = create_storage_location(organization: @org, name: "Shelf")
    @part = create_part(organization: @org, name: "Resistor")
    travel_to Time.utc(2026, 10, 22, 12)
  end

  test "counts stock-outs in the window, not moves, loans, adjustments, ins or older outs" do
    stock(500, days_ago: 200)
    use(10, days_ago: 100) # before the 90-day window
    use(4, days_ago: 30)
    use(6, days_ago: 2, reason: "Build PRJ-1")
    use(3, days_ago: 5, reason: "Moved to Drawer", transfer: true)
    use(3, days_ago: 5, reason: "Took them to the other room (via Claude)", transfer: true)
    loan = @org.loans.new(borrower_name: "Bob")
    loan.loan_lines.build(part: @part, storage_location: @shelf, quantity: 2)
    loan.lend!(user: create_user)
    StockMovement.create!(organization: @org, part: @part, storage_location: @shelf, movement_type: "adjustment",
                          quantity_delta: -7, created_at: 3.days.ago)

    entry = PartConsumption.new(@org).for_part(@part)
    assert_equal 10, entry.consumed
    assert_equal 2, entry.movements
    assert_equal 90, entry.days
    assert_equal 2.days.ago.to_i, entry.last_used_at.to_i
  end

  test "a stock-out counts whatever its reason says, unless it's marked as a transfer" do
    stock(100, days_ago: 20)
    use(4, days_ago: 3, reason: "Moved to the client's board")

    assert_equal 4, PartConsumption.new(@org).for_part(@part).consumed
  end

  test "suggests the threshold that holds the cover days of use, rated over the part's history" do
    stock(100, days_ago: 20)
    use(25, days_ago: 15)
    use(15, days_ago: 1)

    entry = PartConsumption.new(@org).for_part(@part)
    assert_equal 20, entry.days
    assert_in_delta 2.0, entry.daily_rate
    assert_equal 30, entry.cover_days
    assert_equal 60, entry.suggested_threshold
    assert_in_delta 60.0, entry.monthly_rate
    assert_equal 30, entry.days_left(60)
  end

  test "rates a new part over at least two weeks" do
    stock(100, days_ago: 3)
    use(7, days_ago: 2)
    use(7, days_ago: 1)

    entry = PartConsumption.new(@org).for_part(@part)
    assert_equal 14, entry.days
    assert_equal 30, entry.suggested_threshold
  end

  test "covers the supplier lead time plus a week when it's longer than the setting" do
    @org.update_columns(threshold_cover_days: 10)
    stock(100, days_ago: 100)
    use(45, days_ago: 40)
    use(45, days_ago: 4)

    assert_equal 10, PartConsumption.new(@org).for_part(@part).suggested_threshold

    @part.update!(lead_time_days: 20)
    assert_equal 27, PartConsumption.new(@org).for_part(@part).cover_days

    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, is_preferred: true, lead_time_days: 33)
    entry = PartConsumption.new(@org).for_part(@part)
    assert_equal 40, entry.cover_days
    assert_equal 40, entry.suggested_threshold
  end

  test "makes no suggestion from a single use" do
    stock(100, days_ago: 100)
    use(30, days_ago: 10)

    entry = PartConsumption.new(@org).for_part(@part)
    assert_equal 30, entry.consumed
    assert_nil entry.suggested_threshold
  end

  test "leaves unused parts and other organizations' movements out" do
    other_org = create_organization
    other_part = create_part(organization: other_org)
    other_shelf = create_storage_location(organization: other_org)
    StockMovement.create!(organization: other_org, part: other_part, storage_location: other_shelf, movement_type: "in", quantity_delta: 9)
    StockMovement.create!(organization: other_org, part: other_part, storage_location: other_shelf, movement_type: "out", quantity_delta: -9)
    stock(5, days_ago: 10)

    assert_equal({}, PartConsumption.new(@org).for_parts([ @part.id, other_part.id ]))
  end

  test "totals the last months in the organization's time zone" do
    @org.update_columns(timezone: "Europe/Paris")
    stock(100, days_ago: 200)
    use(4, at: Time.utc(2026, 9, 30, 23, 30)) # already October 1st in Paris
    use(3, at: Time.utc(2026, 8, 10))
    use(2, at: Time.utc(2026, 3, 10)) # older than six months

    months = PartConsumption.new(@org).monthly(@part)
    assert_equal %w[2026-05 2026-06 2026-07 2026-08 2026-09 2026-10], months.map { |m| m[:month] }
    assert_equal [ 0, 0, 0, 3, 0, 4 ], months.map { |m| m[:quantity] }
  end

  private

  def stock(quantity, days_ago:)
    StockMovement.create!(organization: @org, part: @part, storage_location: @shelf, movement_type: "in",
                          quantity_delta: quantity, created_at: days_ago.days.ago)
  end

  def use(quantity, days_ago: nil, at: nil, reason: nil, reference: nil, transfer: false)
    StockMovement.create!(organization: @org, part: @part, storage_location: @shelf, movement_type: "out",
                          quantity_delta: -quantity, reason: reason, reference: reference, transfer: transfer,
                          created_at: at || days_ago.days.ago)
  end
end

require "test_helper"

class StockValuationTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @room = create_storage_location(organization: @org, name: "Lab")
    @drawer = create_storage_location(organization: @org, name: "Drawer", location_type: "drawer", parent: @room)
    @shed = create_storage_location(organization: @org, name: "Shed")
    @supplier = create_supplier(organization: @org)
    @resistors = create_category(organization: @org, name: "Resistors")
    @chips = create_category(organization: @org, name: "Chips")

    @resistor = create_part(organization: @org, category: @resistors, name: "R 10k", unit_price: 0.02)
    @chip = create_part(organization: @org, category: @chips, name: "MCU", unit_price: 3)
    @unpriced = create_part(organization: @org, category: @chips, name: "Mystery")
    @empty = create_part(organization: @org, category: @chips, name: "Gone", unit_price: 100)

    stock(@resistor, @drawer, 1000)
    stock(@chip, @drawer, 4)
    stock(@chip, @shed, 6)
    stock(@unpriced, @shed, 5)
  end

  test "current prices value the stock on hand like the dashboard" do
    valuation = StockValuation.new(@org)

    assert_equal "current", valuation.valuation_method
    assert_equal BigDecimal("50"), valuation.total
    assert_equal @org.total_stock_value, valuation.total
    assert_equal [ @chip, @resistor, @unpriced ], valuation.rows.map(&:part), "most valuable first, empty parts left out"
    assert_equal [ @unpriced ], valuation.unpriced_rows.map(&:part)
    assert_equal %w[current current], valuation.rows.first(2).map(&:source)
  end

  test "breaks the value down by category and top-level zone" do
    valuation = StockValuation.new(@org)

    assert_equal [ [ "Chips", 30, 2 ], [ "Resistors", 20, 1 ] ],
                 valuation.by_category.map { |entry| [ entry[:category].name, entry[:value].to_i, entry[:parts] ] }
    assert_equal [ [ "Lab", 32, 2 ], [ "Shed", 18, 2 ] ],
                 valuation.by_root_zone.map { |entry| [ entry[:zone].name, entry[:value].to_i, entry[:parts] ] }
  end

  test "last purchase price uses the latest received order, else the current price" do
    receive(Date.new(2026, 1, 1), @chip => [ 10, 2 ])
    receive(Date.new(2026, 6, 1), @chip => [ 10, 2.5 ])
    create_order(organization: @org, supplier: @supplier, ordered_at: Date.new(2026, 9, 1))
      .order_lines.create!(part: @chip, quantity: 5, unit_price: 9) # still pending: not a purchase yet

    valuation = StockValuation.new(@org, method: "last")
    chip = valuation.rows.find { |row| row.part == @chip }

    assert_equal BigDecimal("2.5"), chip.unit_value
    assert_equal "purchase", chip.source
    assert_equal "current", valuation.rows.find { |row| row.part == @resistor }.source
    assert_equal BigDecimal("45"), valuation.total
  end

  test "average purchase price weighs each received line by its quantity" do
    receive(Date.new(2026, 1, 1), @chip => [ 30, 2 ])
    receive(Date.new(2026, 6, 1), @chip => [ 10, 4 ])

    chip = StockValuation.new(@org, method: "average").rows.find { |row| row.part == @chip }

    assert_equal BigDecimal("2.5"), chip.unit_value
  end

  test "an unknown method falls back to current prices" do
    assert_equal "current", StockValuation.new(@org, method: "fifo").valuation_method
  end

  test "only the organization's stock and orders count" do
    other = create_organization
    other_part = create_part(organization: other, unit_price: 1000)
    StockMovement.create!(organization: other, part: other_part, storage_location: create_storage_location(organization: other),
                          movement_type: "in", quantity_delta: 10)

    assert_equal BigDecimal("50"), StockValuation.new(@org).total
  end

  private

  def stock(part, location, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  # A received order without crediting stock again.
  def receive(date, lines)
    order = create_order(organization: @org, supplier: @supplier, ordered_at: date)
    lines.each { |part, (quantity, price)| order.order_lines.create!(part: part, quantity: quantity, unit_price: price) }
    order.update_column(:status, "received")
  end
end

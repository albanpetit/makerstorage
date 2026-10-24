require "test_helper"

class ProjectCostTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @drawer = create_storage_location(organization: @org, name: "Drawer")
    @distributor = create_supplier(organization: @org, name: "Distributor")
    @broker = create_supplier(organization: @org, name: "Broker")

    # 10 per copy, 50 in stock, preferred link with a break at 100.
    @resistor = create_part(organization: @org, name: "R 10k")
    PartSupplier.create!(part: @resistor, supplier: @distributor, is_preferred: true, unit_price: 0.10,
                         price_breaks: [ { quantity: 1, unit_price: 0.10 }, { quantity: 100, unit_price: 0.02 } ])
    stock(@resistor, 50)

    # 1 per copy, none in stock, two links and no preferred one.
    @mcu = create_part(organization: @org, name: "MCU")
    PartSupplier.create!(part: @mcu, supplier: @distributor, unit_price: 3,
                         price_breaks: [ { quantity: 1, unit_price: 3 }, { quantity: 10, unit_price: 2 } ])
    PartSupplier.create!(part: @mcu, supplier: @broker, unit_price: 2.5)

    @project = create_project(organization: @org, name: "Blinky")
    @project.project_lines.create!(part: @resistor, quantity: 10, match_type: "mpn")
    @project.project_lines.create!(part: @mcu, quantity: 1, match_type: "mpn")
  end

  test "takes what the stock covers and buys the rest at the price break for the quantity bought" do
    one, ten, hundred = cost.estimates.map { |estimate| estimate.rows.index_by(&:part) }

    assert_equal [ 10, 10, 0 ], split(one[@resistor])
    assert_equal BigDecimal("1"), one[@resistor].cost

    assert_equal [ 100, 50, 50 ], split(ten[@resistor])
    assert_equal BigDecimal("0.1"), ten[@resistor].buy_unit_price, "50 bought: below the 100 break"
    assert_equal BigDecimal("10"), ten[@resistor].cost

    assert_equal [ 1000, 50, 950 ], split(hundred[@resistor])
    assert_equal BigDecimal("0.02"), hundred[@resistor].buy_unit_price
    assert_equal BigDecimal("24"), hundred[@resistor].cost, "50 × 0.10 from stock + 950 × 0.02"
    assert_equal @distributor, hundred[@resistor].supplier
  end

  test "without a preferred supplier, buys from the link cheapest at that quantity" do
    one, ten = cost.estimates([ 1, 10 ]).map { |estimate| estimate.rows.index_by(&:part)[@mcu] }

    assert_equal [ @broker, BigDecimal("2.5") ], [ one.supplier, one.buy_unit_price ]
    assert_equal [ @distributor, BigDecimal("2") ], [ ten.supplier, ten.buy_unit_price ]
  end

  test "the preferred supplier wins over a cheaper one" do
    @mcu.part_suppliers.find_by(supplier: @distributor).update!(is_preferred: true)

    row = cost(@project.reload).estimate(1).rows.find { |r| r.part == @mcu }
    assert_equal [ @distributor, BigDecimal("3") ], [ row.supplier, row.buy_unit_price ]
  end

  test "totals split stock and purchases, per copy too, and are complete when everything is priced" do
    estimate = cost.estimate(10)

    assert_equal BigDecimal("5"), estimate.stock_value
    assert_equal BigDecimal("25"), estimate.purchase_cost, "50 × 0.10 + 10 × 2"
    assert_equal BigDecimal("30"), estimate.total
    assert_equal BigDecimal("3"), estimate.per_unit
    assert estimate.complete?
    assert_equal [ @mcu, @resistor ], estimate.rows.map(&:part), "costliest first"
  end

  test "flags parts with no price and lines not in the inventory instead of counting them as free" do
    unpriced = create_part(organization: @org, name: "Mystery")
    stock(unpriced, 3)
    @project.project_lines.create!(part: unpriced, quantity: 1, match_type: "name")
    @project.project_lines.create!(designation: "Custom coil", quantity: 2, match_type: "none")

    estimate = cost(@project.reload).estimate(1)

    assert_not estimate.complete?
    assert_equal [ unpriced ], estimate.unpriced_rows.map(&:part)
    assert_equal [ "Custom coil" ], estimate.unmatched_lines.map(&:designation)
    assert_equal BigDecimal("3.5"), estimate.total, "1 × 0.10 × 10 + 2.50: the unpriced part adds nothing"
  end

  test "stock reserved by an earlier project isn't counted as available" do
    other = create_project(organization: @org, name: "Earlier", status: "confirmed", reserved_at: 1.day.ago)
    other.project_lines.create!(part: @resistor, quantity: 45, match_type: "mpn")

    row = cost(@project.reload).estimate(1).rows.find { |r| r.part == @resistor }
    assert_equal [ 5, 5 ], [ row.from_stock, row.to_buy ]
  end

  test "an empty project costs nothing and is complete" do
    estimate = cost(create_project(organization: @org)).estimate(5)

    assert_empty estimate.rows
    assert_equal 0, estimate.total
    assert estimate.complete?
  end

  test "quantities adds a valid typed quantity to 1, 10 and 100" do
    assert_equal [ 1, 10, 25, 100 ], ProjectCost.quantities("25")
    assert_equal [ 1, 10, 100, 500 ], ProjectCost.quantities(500)
    assert_equal [ 1, 10, 100 ], ProjectCost.quantities("10")
    [ nil, "", "abc", "0", "-3", "2.5", ProjectCost::MAX_QUANTITY + 1 ].each do |value|
      assert_equal ProjectCost::DEFAULT_QUANTITIES, ProjectCost.quantities(value), value.inspect
    end
  end

  private

  def split(row)
    [ row.required, row.from_stock, row.to_buy ]
  end

  def cost(project = @project)
    ProjectCost.new(project)
  end

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @drawer, movement_type: "in", quantity_delta: quantity)
  end
end

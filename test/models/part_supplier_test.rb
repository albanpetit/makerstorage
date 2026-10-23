require "test_helper"

class PartSupplierTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @part = create_part(organization: @org)
  end

  test "a preferred supplier price sets the part's unit_price" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)

    assert_equal 1.5, @part.reload.unit_price.to_f
  end

  test "repricing the preferred supplier updates the part's unit_price" do
    supplier = create_supplier(organization: @org)
    ps = PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)

    ps.update!(unit_price: 2.25)

    assert_equal 2.25, @part.reload.unit_price.to_f
  end

  test "a non-preferred supplier price does not change the part's unit_price" do
    @part.update!(unit_price: 9)
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: false)

    assert_equal 9, @part.reload.unit_price.to_f
  end

  test "switching the preferred supplier re-syncs the part's unit_price" do
    first = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 1, is_preferred: true)
    second = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 2, is_preferred: false)
    assert_equal 1, @part.reload.unit_price.to_f

    second.update!(is_preferred: true)

    assert_equal 2, @part.reload.unit_price.to_f
    assert_not first.reload.is_preferred?
  end

  test "a preferred supplier without a price leaves a manual unit_price untouched" do
    @part.update!(unit_price: 3.5)
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: nil, is_preferred: true)

    assert_equal 3.5, @part.reload.unit_price.to_f
  end

  test "removing the preferred supplier keeps the last synced price" do
    supplier = create_supplier(organization: @org)
    ps = PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)
    assert_equal 1.5, @part.reload.unit_price.to_f

    ps.destroy

    assert_equal 1.5, @part.reload.unit_price.to_f
  end

  test "price breaks are cleaned up: sorted, blank rows dropped, one price per quantity" do
    link = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), price_breaks: [
      { quantity: "100", unit_price: "0,05" },
      { "quantity" => 10, "unit_price" => 0.08 },
      { quantity: "", unit_price: "" },
      { quantity: 100, unit_price: "0.045" }
    ])

    assert_equal [ { "quantity" => 10, "unit_price" => "0.08" }, { "quantity" => 100, "unit_price" => "0.045" } ], link.reload.price_breaks
  end

  test "a link given only price breaks takes the first break as its unit price" do
    link = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org),
                                price_breaks: [ { quantity: 10, unit_price: "0.08" }, { quantity: 1, unit_price: "0.12" } ])

    assert_equal 0.12, link.unit_price.to_f
  end

  test "unreadable or impossible price breaks are refused" do
    supplier = create_supplier(organization: @org)
    [
      [ { quantity: "ten", unit_price: "1" } ],
      [ { quantity: 0, unit_price: "1" } ],
      [ { quantity: 10, unit_price: "-1" } ],
      [ { quantity: 10, unit_price: "cheap" } ]
    ].each do |rows|
      link = PartSupplier.new(part: @part, supplier: supplier, price_breaks: rows)
      assert_not link.valid?, rows.inspect
      assert link.errors.added?(:price_breaks, :invalid_price_breaks), rows.inspect
    end

    too_many = (1..(PartSupplier::MAX_PRICE_BREAKS + 1)).map { |n| { quantity: n, unit_price: "1" } }
    link = PartSupplier.new(part: @part, supplier: supplier, price_breaks: too_many)
    assert_not link.valid?
    assert link.errors.added?(:price_breaks, :too_many_price_breaks, count: PartSupplier::MAX_PRICE_BREAKS)
  end

  test "unit_price_for picks the break for the quantity" do
    link = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 0.15,
                                price_breaks: [ { quantity: 10, unit_price: "0.08" }, { quantity: 100, unit_price: "0.05" } ])

    assert_equal 0.15, link.unit_price_for(5).to_f, "below the first break: the plain unit price"
    assert_equal 0.08, link.unit_price_for(10).to_f
    assert_equal 0.08, link.unit_price_for(99).to_f
    assert_equal 0.05, link.unit_price_for(5000).to_f
    assert_equal 0.15, link.unit_price_for(nil).to_f
  end

  test "unit_price_for without breaks is the unit price" do
    link = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 0.15)

    assert_equal 0.15, link.unit_price_for(1000).to_f
  end

  test "unit prices keep four decimals" do
    link = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: "0.0021", is_preferred: true)

    assert_equal BigDecimal("0.0021"), link.reload.unit_price
    assert_equal BigDecimal("0.0021"), @part.reload.unit_price
  end
end

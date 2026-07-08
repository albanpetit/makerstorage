require "test_helper"

class PartTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @category = create_category(organization: @org)
  end

  test "valid with organization, category, and name" do
    part = Part.new(organization: @org, category: @category, name: "Resistor 10k")
    assert part.valid?
  end

  test "defaults unit to piece" do
    part = create_part(organization: @org, category: @category)
    assert_equal "piece", part.unit
  end

  test "rejects a unit outside the allowed list" do
    part = Part.new(organization: @org, category: @category, name: "X", unit: "kilogram")
    assert_not part.valid?
    assert_includes part.errors[:unit], "is not included in the list"
  end

  test "accepts every declared unit" do
    Part::UNITS.each do |unit|
      part = Part.new(organization: @org, category: @category, name: "Widget", unit: unit)
      assert part.valid?, "expected unit #{unit} to be valid"
    end
  end

  test "category must belong to the same organization" do
    other_org = create_organization
    other_category = create_category(organization: other_org)
    part = Part.new(organization: @org, category: other_category, name: "X")
    assert_not part.valid?
    assert_includes part.errors[:category], "must belong to the same organization"
  end

  test "total_quantity sums part_storages across locations" do
    part = create_part(organization: @org, category: @category)
    loc_a = create_storage_location(organization: @org, name: "A")
    loc_b = create_storage_location(organization: @org, name: "B")
    PartStorage.create!(part: part, storage_location: loc_a, quantity: 30)
    PartStorage.create!(part: part, storage_location: loc_b, quantity: 12)

    assert_equal 42, part.total_quantity
  end

  test "total_quantity is zero with no stock" do
    part = create_part(organization: @org, category: @category)
    assert_equal 0, part.total_quantity
  end

  test "low_stock? and out_of_stock?" do
    part = create_part(organization: @org, category: @category, min_stock_threshold: 50)
    location = create_storage_location(organization: @org)

    assert part.out_of_stock?
    assert part.low_stock?

    PartStorage.create!(part: part, storage_location: location, quantity: 20)
    part.reload
    assert_not part.out_of_stock?
    assert part.low_stock?

    PartStorage.find_by(part: part, storage_location: location).update!(quantity: 100)
    part.reload
    assert_not part.low_stock?
  end

  test "stock_status reflects thresholds" do
    part = create_part(organization: @org, category: @category, min_stock_threshold: 10)
    location = create_storage_location(organization: @org)

    assert_equal :out_of_stock, part.stock_status

    PartStorage.create!(part: part, storage_location: location, quantity: 5)
    part.reload
    assert_equal :low_stock, part.stock_status

    PartStorage.find_by(part: part, storage_location: location).update!(quantity: 50)
    part.reload
    assert_equal :sufficient, part.stock_status
  end

  test "quantity_to_order accounts for current stock against target_stock" do
    part = create_part(organization: @org, category: @category, target_stock: 100)
    location = create_storage_location(organization: @org)
    PartStorage.create!(part: part, storage_location: location, quantity: 30)
    part.reload

    assert_equal 70, part.quantity_to_order
  end

  test "quantity_to_order is zero without a target_stock" do
    part = create_part(organization: @org, category: @category, target_stock: nil)
    assert_equal 0, part.quantity_to_order
  end

  test "search matches across name, mpn, sku, manufacturer, value, and barcode, case-insensitively" do
    resistor = create_part(organization: @org, category: @category, name: "Resistor 10k", mpn: "RES-10K-0603")
    capacitor = create_part(organization: @org, category: @category, name: "Capacitor 100nF", mpn: "CAP-100N")

    assert_includes Part.search("resistor"), resistor
    assert_not_includes Part.search("resistor"), capacitor
    assert_includes Part.search("RES-10K"), resistor
    assert_includes Part.search("100nf"), capacitor
  end

  test "search returns nothing for a query matching no fields" do
    create_part(organization: @org, category: @category, name: "Resistor 10k")
    assert_empty Part.search("nonexistent-query-xyz")
  end
end

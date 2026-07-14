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

  test "image_source_url accepts blank and http(s) URLs but rejects other schemes" do
    part = Part.new(organization: @org, category: @category, name: "Widget")

    part.image_source_url = ""
    assert part.valid?, "blank image_source_url should be allowed"

    part.image_source_url = "https://www.mouser.com/img.png"
    assert part.valid?, "https URL should be allowed"

    part.image_source_url = "javascript:alert(1)"
    assert_not part.valid?
    assert_includes part.errors[:image_source_url], "is invalid"
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

  # IPN generation

  test "assigns an incremental ipn on create and advances the org counter" do
    org = create_organization(ipn_generation_mode: "incremental", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 1)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category)
    assert_equal "MS-00001", part.ipn
    assert_equal 2, org.reload.ipn_next_sequence

    second = create_part(organization: org, category: category)
    assert_equal "MS-00002", second.ipn
    assert_equal 3, org.reload.ipn_next_sequence
  end

  test "ipn includes the category code when enabled" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: true, ipn_separator: "-", ipn_digits: 4, ipn_next_sequence: 7)
    category = create_category(organization: org, code: "RES")

    part = create_part(organization: org, category: category)
    assert_equal "MS-RES-0007", part.ipn
  end

  test "does not auto-generate an ipn in manual mode" do
    org = create_organization(ipn_generation_mode: "manual", ipn_next_sequence: 12)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category)
    assert_nil part.ipn
    assert_equal 12, org.reload.ipn_next_sequence, "counter must not advance without a generated ipn"
  end

  test "keeps an explicitly supplied ipn and leaves the counter untouched" do
    org = create_organization(ipn_generation_mode: "incremental", ipn_next_sequence: 5)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category, ipn: "CUSTOM-1")
    assert_equal "CUSTOM-1", part.ipn
    assert_equal 5, org.reload.ipn_next_sequence
  end

  test "ipn is unique per organization" do
    create_part(organization: @org, category: @category, ipn: "MS-0001")
    duplicate = Part.new(organization: @org, category: @category, name: "Dupe", ipn: "MS-0001")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ipn], "has already been taken"
  end

  test "skips a taken reference by redrawing from the next seed" do
    org = create_organization(ipn_generation_mode: "random", ipn_charset: "numeric", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 6, ipn_next_sequence: 5)
    category = create_category(organization: org)

    # Occupy the reference the counter would draw first, forcing a redraw.
    taken = org.next_ipn(sequence: 5)
    create_part(organization: org, category: category, ipn: taken)

    part = create_part(organization: org, category: category)
    assert_equal org.next_ipn(sequence: 6), part.ipn
    assert_not_equal taken, part.ipn
    assert_equal 7, org.reload.ipn_next_sequence
  end

  test "the same ipn may exist in different organizations" do
    create_part(organization: @org, category: @category, ipn: "MS-0001")

    other_org = create_organization
    other_part = Part.new(organization: other_org, category: create_category(organization: other_org), name: "Elsewhere", ipn: "MS-0001")
    assert other_part.valid?
  end

  test "barcode is unique per organization" do
    create_part(organization: @org, category: @category, barcode: "123456789012")
    duplicate = Part.new(organization: @org, category: @category, name: "Dupe", barcode: "123456789012")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:barcode], "has already been taken"
  end

  test "the same barcode may exist in different organizations" do
    create_part(organization: @org, category: @category, barcode: "123456789012")

    other_org = create_organization
    other_part = Part.new(organization: other_org, category: create_category(organization: other_org), name: "Elsewhere", barcode: "123456789012")
    assert other_part.valid?
  end
end

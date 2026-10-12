require "test_helper"

class BomParser::MatcherTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @matcher = BomParser::Matcher.new(@org)
  end

  test "matches a supplier part number when no part carries it as its own SKU" do
    part = create_part(organization: @org, name: "Resistor 4.7k")
    PartSupplier.create!(part: part, supplier: create_supplier(organization: @org), supplier_sku: "C23162")

    assert_equal [ part, "supplier_sku" ], @matcher.match(line(sku: "c23162"))
  end

  test "own SKU wins over a supplier part number" do
    own = create_part(organization: @org, sku: "C23162")
    other = create_part(organization: @org)
    PartSupplier.create!(part: other, supplier: create_supplier(organization: @org), supplier_sku: "C23162")

    assert_equal [ own, "sku" ], @matcher.match(line(sku: "C23162"))
  end

  test "matches value + footprint against the part's footprint or package" do
    by_footprint = create_part(organization: @org, value: "100 nF", footprint: create_footprint(organization: @org, name: "0603"))
    by_package = create_part(organization: @org, value: "4.7kΩ", package_type: "0805")
    soic = create_part(organization: @org, value: "NE555", package_type: "SOIC-8")

    assert_equal [ by_footprint, "value_footprint" ], @matcher.match(line(value: "100nF", footprint: "Capacitor_SMD:C_0603_1608Metric"))
    assert_equal [ by_package, "value_footprint" ], @matcher.match(line(value: "4k7", footprint: "Resistor_SMD:R_0805_2012Metric"))
    assert_equal [ soic, "value_footprint" ], @matcher.match(line(value: "ne555", footprint: "Package_SO:SOIC-8_3.9x4.9mm_P1.27mm"))
  end

  test "value alone, or a different footprint, is not a match" do
    create_part(organization: @org, name: "Cap", value: "100nF", package_type: "0603")

    assert_equal [ nil, "none" ], @matcher.match(line(value: "100nF"))
    assert_equal [ nil, "none" ], @matcher.match(line(value: "100nF", footprint: "Capacitor_SMD:C_1206_3216Metric"))
  end

  test "MPN comes before value + footprint" do
    create_part(organization: @org, value: "10k", package_type: "0603")
    exact = create_part(organization: @org, mpn: "RC0603FR-0710KL", value: "10k", package_type: "0603")

    assert_equal [ exact, "mpn" ], @matcher.match(line(mpn: "RC0603FR-0710KL", value: "10k", footprint: "R_0603_1608Metric"))
  end

  test "never matches another organization's parts" do
    other = create_organization
    part = create_part(organization: other, mpn: "BME280", sku: "SKU-1", value: "10k", package_type: "0603")
    PartSupplier.create!(part: part, supplier: create_supplier(organization: other), supplier_sku: "C1")

    [ line(mpn: "BME280"), line(sku: "SKU-1"), line(sku: "C1"), line(value: "10k", footprint: "R_0603_1608Metric") ].each do |l|
      assert_equal [ nil, "none" ], @matcher.match(l)
    end
  end

  test "normalizes component values" do
    assert_equal "4.7k", BomParser::Matcher.normalize_value("4k7")
    assert_equal "4.7k", BomParser::Matcher.normalize_value("4.7 kΩ")
    assert_equal "2.2", BomParser::Matcher.normalize_value("2R2")
    assert_equal "100n", BomParser::Matcher.normalize_value("100nF")
    assert_equal "10u", BomParser::Matcher.normalize_value("10µF")
    assert_equal "1u", BomParser::Matcher.normalize_value("1u0")
  end

  private

  def line(designation: nil, mpn: nil, sku: nil, value: nil, footprint: nil)
    { designation: designation, mpn: mpn, sku: sku, value: value, footprint: footprint }
  end
end

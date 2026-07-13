require "test_helper"

class SupplierCatalog::DescriptionParserTest < ActiveSupport::TestCase
  test "recovers value, package, tolerance and power from a passive description" do
    parsed = SupplierCatalog::DescriptionParser.parse(
      "Thick Film Resistors - SMD 0805, 10kOhms, 1%, 1/8W"
    )

    assert_equal "0805", parsed[:package_type]
    assert_equal "10kOhms", parsed[:value]
    assert_equal "1%", parsed[:tolerance]
    assert_equal "1/8W", parsed[:power_rating]
  end

  test "recovers a package family with a pin count" do
    parsed = SupplierCatalog::DescriptionParser.parse("IC MCU 32BIT LQFP-64")
    assert_equal "LQFP-64", parsed[:package_type]
  end

  test "yields nothing for a non-passive description" do
    parsed = SupplierCatalog::DescriptionParser.parse("EEPROM 1KB SPI SER CMOS")

    assert_nil parsed[:value]
    assert_nil parsed[:package_type]
    assert_nil parsed[:tolerance]
  end

  test "returns an empty hash for blank text" do
    assert_equal({}, SupplierCatalog::DescriptionParser.parse(""))
    assert_equal({}, SupplierCatalog::DescriptionParser.parse(nil))
  end
end

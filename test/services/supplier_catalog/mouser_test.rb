require "test_helper"

class SupplierCatalog::MouserTest < ActiveSupport::TestCase
  # A representative Mouser keyword-search response (trimmed to the fields we map).
  def sample_payload(parts:)
    { "Errors" => [], "SearchResults" => { "NumberOfResult" => parts.length, "Parts" => parts } }
  end

  def sample_part
    {
      "Description" => "RES 10K OHM 1% 1/8W 0805",
      "ManufacturerPartNumber" => "RC0805FR-0710KL",
      "Manufacturer" => "YAGEO",
      "MouserPartNumber" => "603-RC0805FR-0710KL",
      "DataSheetUrl" => "https://www.mouser.com/datasheet/2/447/foo.pdf",
      "ImagePath" => "https://www.mouser.com/images/foo.jpg",
      "ProductDetailUrl" => "https://www.mouser.com/pd/foo",
      "ROHSStatus" => "RoHS Compliant",
      "PriceBreaks" => [
        { "Quantity" => 10, "Price" => "€0,05", "Currency" => "EUR" },
        { "Quantity" => 1, "Price" => "€0,10", "Currency" => "EUR" }
      ],
      "ProductAttributes" => [
        { "AttributeName" => "Resistance", "AttributeValue" => "10 kOhms" },
        { "AttributeName" => "Tolerance", "AttributeValue" => "1 %" },
        { "AttributeName" => "Power (Watts)", "AttributeValue" => "0.125W" },
        { "AttributeName" => "Package / Case", "AttributeValue" => "0805" }
      ]
    }
  end

  def build_provider(payload)
    provider = SupplierCatalog::Mouser.new(api_key: "test-key")
    provider.define_singleton_method(:perform_request) { |_body| payload }
    provider
  end

  test "maps Mouser fields onto normalized part attributes" do
    result = build_provider(sample_payload(parts: [ sample_part ])).search("RC0805FR-0710KL").first

    assert_equal "RES 10K OHM 1% 1/8W 0805", result.name
    assert_equal "RC0805FR-0710KL", result.mpn
    assert_equal "YAGEO", result.manufacturer
    assert_equal "10 kOhms", result.value
    assert_equal "0805", result.package_type
    assert_equal "1 %", result.tolerance
    assert_equal "0.125W", result.power_rating
    assert_equal "603-RC0805FR-0710KL", result.supplier_sku
    assert_equal "https://www.mouser.com/datasheet/2/447/foo.pdf", result.datasheet_url
    assert_equal "https://www.mouser.com/images/foo.jpg", result.image_url
    assert_equal "mouser", result.provider
    assert result.rohs_compliant
  end

  test "uses the lowest-quantity price break and normalizes the currency format" do
    result = build_provider(sample_payload(parts: [ sample_part ])).search("x").first
    assert_equal "0.1", result.unit_price
  end

  test "recovers value/package/tolerance/power from the description when attributes are only packaging" do
    part = {
      "Description" => "Thick Film Resistors - SMD General Purpose Chip Resistor 0805, 10kOhms, 1%, 1/8W",
      "ManufacturerPartNumber" => "RC0805FR-0710KL",
      "ProductAttributes" => [
        { "AttributeName" => "Conditionnement", "AttributeValue" => "Reel" },
        { "AttributeName" => "Quantité standard du lot", "AttributeValue" => "5000" }
      ]
    }
    result = build_provider(sample_payload(parts: [ part ])).search("x").first

    assert_equal "0805", result.package_type
    assert_equal "10kOhms", result.value
    assert_equal "1%", result.tolerance
    assert_equal "1/8W", result.power_rating
  end

  test "reads French structured attribute names" do
    part = sample_part.merge(
      "ProductAttributes" => [
        { "AttributeName" => "Boîtier", "AttributeValue" => "0402" },
        { "AttributeName" => "Résistance", "AttributeValue" => "4.7 kOhms" },
        { "AttributeName" => "Tolérance", "AttributeValue" => "5 %" }
      ]
    )
    result = build_provider(sample_payload(parts: [ part ])).search("x").first

    assert_equal "0402", result.package_type
    assert_equal "4.7 kOhms", result.value
    assert_equal "5 %", result.tolerance
  end

  test "does not invent parametric values for non-passive descriptions" do
    part = {
      "Description" => "EEPROM 1KB SPI SER CMOS EEPROM -LOW VCC RANGE",
      "ManufacturerPartNumber" => "NV25010DWVLT3G",
      "ProductAttributes" => []
    }
    result = build_provider(sample_payload(parts: [ part ])).search("x").first

    assert_nil result.value
    assert_nil result.package_type
    assert_nil result.tolerance
  end

  test "returns an empty array when there are no matches" do
    assert_empty build_provider(sample_payload(parts: [])).search("nope")
  end

  test "returns every match for the pick-list when multiple parts are returned" do
    second = sample_part.merge("ManufacturerPartNumber" => "RC0805FR-0710KL-ALT")
    results = build_provider(sample_payload(parts: [ sample_part, second ])).search("x")
    assert_equal 2, results.length
  end

  test "flags non-RoHS status as not compliant" do
    part = sample_part.merge("ROHSStatus" => "RoHS Non-Compliant")
    result = build_provider(sample_payload(parts: [ part ])).search("x").first
    refute result.rohs_compliant
  end

  test "raises LookupError when the API reports an error" do
    payload = { "Errors" => [ { "Message" => "Something broke" } ], "SearchResults" => nil }
    error = assert_raises(SupplierCatalog::LookupError) { build_provider(payload).search("x") }
    assert_match "Something broke", error.message
  end

  test "translates a rejected API key into an actionable message" do
    payload = {
      "Errors" => [ { "Code" => "Invalid", "Message" => "Invalid unique identifier.", "ResourceKey" => "InvalidIdentifier", "PropertyName" => "API Key" } ],
      "SearchResults" => nil
    }
    error = assert_raises(SupplierCatalog::LookupError) { build_provider(payload).search("x") }
    assert_match(/rejected the API key/, error.message)
    assert_match(/Settings/, error.message)
  end

  # --- Order/Cart API -------------------------------------------------------

  def order_provider(payload)
    provider = SupplierCatalog::Mouser.new(api_key: "search-key", order_api_key: "order-key")
    provider.define_singleton_method(:order_request) { |*_args, **_kwargs| payload }
    provider
  end

  test "import_order normalizes a fetched Mouser order" do
    payload = {
      "WebOrderNumber" => "9988",
      "OrderStatusDisplay" => "Shipped",
      "OrderDate" => "2026-07-01",
      "CurrencyCode" => "EUR",
      "MerchandiseTotal" => "€12,50",
      "OrderLines" => [
        {
          "MfrPartNumber" => "RC0805FR-0710KL", "Manufacturer" => "YAGEO",
          "MouserPartNumber" => "603-RC0805FR-0710KL", "Description" => "RES 10K",
          "Quantity" => 100, "UnitPrice" => "€0,05"
        }
      ]
    }

    result = order_provider(payload).import_order("9988")
    assert_equal "9988", result.order_number
    assert_equal "Shipped", result.status
    assert_equal "12.5", result.total
    line = result.lines.first
    assert_equal "RC0805FR-0710KL", line.mpn
    assert_equal "603-RC0805FR-0710KL", line.supplier_sku
    assert_equal 100, line.quantity
    assert_equal "0.05", line.unit_price
  end

  test "create_cart normalizes a built Mouser cart" do
    payload = {
      "CartKey" => "abc-123",
      "CurrencyCode" => "EUR",
      "MerchandiseTotal" => "€1,00",
      "CartItems" => [
        { "MouserPartNumber" => "603-x", "Quantity" => 5, "UnitPrice" => "€0,20", "Description" => "part" }
      ]
    }

    result = order_provider(payload).create_cart([ { supplier_sku: "603-x", quantity: 5 } ])
    assert_equal "abc-123", result.cart_key
    assert_equal "1.0", result.merchandise_total
    assert_equal 1, result.lines.size
    assert_equal "603-x", result.lines.first.supplier_sku
  end

  test "order_request raises when no order key is configured" do
    provider = SupplierCatalog::Mouser.new(api_key: "search-key")
    assert_raises(SupplierCatalog::LookupError) { provider.import_order("1") }
  end
end

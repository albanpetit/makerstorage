require "test_helper"

class SupplierCatalog::DigikeyTest < ActiveSupport::TestCase
  # A representative DigiKey Product Information v4 keyword-search response
  # (trimmed to the fields we map).
  def sample_payload(products:)
    { "ProductsCount" => products.length, "Products" => products }
  end

  def sample_product
    {
      "Description" => {
        "ProductDescription" => "RES 10K OHM 1% 1/8W 0805",
        "DetailedDescription" => "10 kOhms ±1% 0.125W, 1/8W Chip Resistor 0805"
      },
      "Manufacturer" => { "Id" => 1, "Name" => "YAGEO" },
      "ManufacturerProductNumber" => "RC0805FR-0710KL",
      "UnitPrice" => 0.10,
      "DatasheetUrl" => "https://www.digikey.com/datasheet/foo.pdf",
      "PhotoUrl" => "https://www.digikey.com/photos/foo.jpg",
      "ProductUrl" => "https://www.digikey.com/pd/foo",
      "Classifications" => { "RohsStatus" => "ROHS3 Compliant" },
      "ProductVariations" => [
        {
          "DigiKeyProductNumber" => "311-10.0KCRCT-ND",
          "StandardPricing" => [
            { "BreakQuantity" => 10, "UnitPrice" => 0.05 },
            { "BreakQuantity" => 1, "UnitPrice" => 0.12 }
          ]
        }
      ],
      "Parameters" => [
        { "ParameterText" => "Resistance", "ValueText" => "10 kOhms" },
        { "ParameterText" => "Tolerance", "ValueText" => "±1%" },
        { "ParameterText" => "Power (Watts)", "ValueText" => "0.125W, 1/8W" },
        { "ParameterText" => "Supplier Device Package", "ValueText" => "0805" }
      ]
    }
  end

  # Stubs both HTTP seams so no network is touched.
  def build_provider(payload)
    provider = SupplierCatalog::Digikey.new(client_id: "cid", client_secret: "csecret")
    provider.define_singleton_method(:access_token) { "test-token" }
    provider.define_singleton_method(:perform_request) { |_body| payload }
    provider
  end

  test "maps DigiKey fields onto normalized part attributes" do
    result = build_provider(sample_payload(products: [ sample_product ])).search("RC0805FR-0710KL").first

    assert_equal "RES 10K OHM 1% 1/8W 0805", result.name
    assert_equal "RC0805FR-0710KL", result.mpn
    assert_equal "YAGEO", result.manufacturer
    assert_equal "10 kOhms", result.value
    assert_equal "0805", result.package_type
    assert_equal "±1%", result.tolerance
    assert_equal "0.125W, 1/8W", result.power_rating
    assert_equal "311-10.0KCRCT-ND", result.supplier_sku
    assert_equal "https://www.digikey.com/datasheet/foo.pdf", result.datasheet_url
    assert_equal "https://www.digikey.com/photos/foo.jpg", result.image_url
    assert_equal "https://www.digikey.com/pd/foo", result.product_url
    assert_equal "digikey", result.provider
    assert result.rohs_compliant
  end

  test "uses the headline UnitPrice as a numeric string" do
    result = build_provider(sample_payload(products: [ sample_product ])).search("x").first
    assert_equal "0.1", result.unit_price
  end

  test "falls back to the lowest-quantity price break when UnitPrice is missing" do
    product = sample_product.merge("UnitPrice" => nil)
    result = build_provider(sample_payload(products: [ product ])).search("x").first
    assert_equal "0.12", result.unit_price
  end

  test "treats a '-' parameter value as blank and recovers from the description" do
    product = sample_product.merge(
      "Parameters" => [
        { "ParameterText" => "Resistance", "ValueText" => "-" },
        { "ParameterText" => "Supplier Device Package", "ValueText" => "-" }
      ]
    )
    result = build_provider(sample_payload(products: [ product ])).search("x").first

    # Recovered from "10 kOhms ±1% 0.125W, 1/8W ... 0805" in the description.
    assert_equal "0805", result.package_type
    assert_equal "10 kOhms", result.value
  end

  test "does not invent parametric values for non-passive descriptions" do
    product = {
      "Description" => { "ProductDescription" => "EEPROM 1KB SPI SER CMOS", "DetailedDescription" => "" },
      "ManufacturerProductNumber" => "NV25010DWVLT3G",
      "Parameters" => []
    }
    result = build_provider(sample_payload(products: [ product ])).search("x").first

    assert_nil result.value
    assert_nil result.package_type
    assert_nil result.tolerance
  end

  test "returns an empty array when there are no matches" do
    assert_empty build_provider(sample_payload(products: [])).search("nope")
  end

  test "returns every match for the pick-list when multiple products are returned" do
    second = sample_product.merge("ManufacturerProductNumber" => "RC0805FR-0710KL-ALT")
    results = build_provider(sample_payload(products: [ sample_product, second ])).search("x")
    assert_equal 2, results.length
  end

  test "flags a non-RoHS status as not compliant" do
    product = sample_product.merge("Classifications" => { "RohsStatus" => "Not Compliant" })
    result = build_provider(sample_payload(products: [ product ])).search("x").first
    refute result.rohs_compliant
  end

  # --- Order Status API + OAuth token helpers -------------------------------

  def order_provider(payload)
    provider = SupplierCatalog::Digikey.new(client_id: "cid", client_secret: "csecret", access_token: "user-token")
    provider.define_singleton_method(:order_get) { |_url| payload }
    provider
  end

  test "import_order normalizes a fetched DigiKey sales order" do
    payload = {
      "SalesOrderId" => 55102,
      "OrderStatus" => "Shipped",
      "DateEntered" => "2026-07-01",
      "Currency" => "EUR",
      "TotalPrice" => "18.20",
      "LineItems" => [
        {
          "ManufacturerPartNumber" => "ATMEGA328P-AU", "Manufacturer" => "Microchip",
          "DigiKeyPartNumber" => "ATMEGA328P-AU-ND", "ProductDescription" => "IC MCU 8BIT",
          "Quantity" => 50, "UnitPrice" => "0.25"
        }
      ]
    }

    result = order_provider(payload).import_order("55102")
    assert_equal "55102", result.order_number
    assert_equal "Shipped", result.status
    line = result.lines.first
    assert_equal "ATMEGA328P-AU", line.mpn
    assert_equal "ATMEGA328P-AU-ND", line.supplier_sku
    assert_equal 50, line.quantity
    assert_equal "0.25", line.unit_price
  end

  test "import_order raises without a connected account token" do
    provider = SupplierCatalog::Digikey.new(client_id: "cid", client_secret: "csecret")
    assert_raises(SupplierCatalog::LookupError) { provider.import_order("1") }
  end

  test "refresh_token posts the refresh grant and returns the token hash" do
    captured = nil
    replacement = lambda do |form|
      captured = form
      { "access_token" => "new-a", "refresh_token" => "new-r", "expires_in" => 1800 }
    end

    stub_singleton(SupplierCatalog::Digikey, :post_token, replacement) do
      tokens = SupplierCatalog::Digikey.refresh_token(client_id: "c", client_secret: "s", refresh_token: "old")
      assert_equal "new-a", tokens["access_token"]
    end
    assert_equal "refresh_token", captured[:grant_type]
    assert_equal "old", captured[:refresh_token]
  end

  test "authorize_url carries the client id, redirect uri and state" do
    url = SupplierCatalog::Digikey.authorize_url(client_id: "cid", redirect_uri: "https://app.test/cb", state: "xyz")
    assert_includes url, "response_type=code"
    assert_includes url, "client_id=cid"
    assert_includes url, "state=xyz"
    assert_includes url, CGI.escape("https://app.test/cb")
  end
end

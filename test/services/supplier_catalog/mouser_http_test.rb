require "test_helper"

# Mouser's HTTP layer, against canned responses: what is sent, and how each
# kind of failure reads to the user.
class SupplierCatalog::MouserHttpTest < ActiveSupport::TestCase
  def provider
    SupplierCatalog::Mouser.new(api_key: "search-key", order_api_key: "order-key")
  end

  test "a search sends the keyword with the search key" do
    payload = { "Errors" => [], "SearchResults" => { "Parts" => [ { "ManufacturerPartNumber" => "RC0805FR-0710KL", "PriceBreaks" => [] } ] } }

    with_fake_http([ 200, payload.to_json ]) do |requests|
      assert_equal [ "RC0805FR-0710KL" ], provider.search(" RC0805FR-0710KL ").map(&:mpn)

      request = requests.sole
      assert_equal "POST", request.method
      assert_equal "search-key", URI.decode_www_form(URI(request.path).query).to_h["apiKey"]
      assert_equal "RC0805FR-0710KL", JSON.parse(request.body).dig("SearchByKeywordRequest", "keyword")
    end
  end

  test "search failures read as the user can act on them" do
    {
      [ 503, "" ] => /Mouser API returned 503/,
      [ 200, "<html>" ] => /unreadable/,
      [ Net::ReadTimeout.new, nil ] => /Could not reach Mouser API/,
      [ 200, { "Errors" => [ { "PropertyName" => "API Key", "Message" => "Invalid unique identifier." } ] }.to_json ] => /rejected the API key/,
      [ 200, { "Errors" => [ { "Message" => "Too many requests" } ] }.to_json ] => /Too many requests/
    }.each do |response, message|
      with_fake_http(response) do
        error = assert_raises(SupplierCatalog::LookupError) { provider.search("X") }
        assert_match message, error.message
      end
    end
  end

  test "an order import sends the order key and reads European prices" do
    order = {
      "Errors" => [], "WebOrderNumber" => "123456", "CurrencyCode" => "EUR", "MerchandiseTotal" => "1.234,50 €",
      "OrderLines" => [ { "MfrPartNumber" => "RC0805FR-0710KL", "MouserPartNumber" => "603-RC0805FR-0710KL", "Quantity" => 100, "UnitPrice" => "0,012 €" } ]
    }

    with_fake_http([ 200, order.to_json ]) do |requests|
      result = provider.import_order("123456")

      query = URI.decode_www_form(URI(requests.sole.path).query).to_h
      assert_equal [ "order-key", "123456" ], query.values_at("apiKey", "webOrderNumber")
      assert_equal "1234.5", result.total
      assert_equal [ [ "RC0805FR-0710KL", 100, "0.012" ] ], result.lines.map { |line| [ line.mpn, line.quantity, line.unit_price ] }
    end
  end

  test "a cart is posted with its items" do
    cart = { "Errors" => [], "CartKey" => "abc", "CartItems" => [ { "MouserPartNumber" => "603-X", "Quantity" => 10, "UnitPrice" => "1,234.5" } ] }

    with_fake_http([ 200, cart.to_json ]) do |requests|
      result = provider.create_cart([ { supplier_sku: "603-X", quantity: 10 } ])

      assert_equal "POST", requests.sole.method
      assert_equal [ { "MouserPartNumber" => "603-X", "Quantity" => 10 } ], JSON.parse(requests.sole.body)["CartItems"]
      assert_equal "abc", result.cart_key
      assert_equal "1234.5", result.lines.sole.unit_price
    end
  end

  test "order API failures read as the user can act on them" do
    { [ 401, "" ] => /Order API returned 401/, [ 200, "nope" ] => /unreadable/, [ Errno::ECONNRESET.new, nil ] => /Could not reach Mouser Order API/ }.each do |response, message|
      with_fake_http(response) do
        error = assert_raises(SupplierCatalog::LookupError) { provider.import_order("1") }
        assert_match message, error.message
      end
    end
  end

  test "the order API needs its own key and sends nothing without it" do
    with_fake_http do |requests|
      error = assert_raises(SupplierCatalog::LookupError) { SupplierCatalog::Mouser.new(api_key: "k").import_order("1") }
      assert_match(/Order API key/, error.message)
      assert_empty requests
    end
  end
end

require "test_helper"

# DigiKey's HTTP layer, against canned responses: what is sent, and how each
# kind of failure reads to the user.
class SupplierCatalog::DigikeyHttpTest < ActiveSupport::TestCase
  TOKEN = [ 200, { "access_token" => "app-token" }.to_json ].freeze

  def provider(access_token: nil)
    SupplierCatalog::Digikey.new(client_id: "cid", client_secret: "secret-#{SecureRandom.hex(4)}", access_token: access_token)
  end

  test "a search fetches an app token, then sends the keyword with it" do
    products = { "Products" => [ { "ManufacturerProductNumber" => "SN74HC595N", "Description" => { "ProductDescription" => "IC" } } ] }

    with_fake_http(TOKEN, [ 200, products.to_json ]) do |requests|
      results = provider.search(" SN74HC595N ")

      assert_equal [ "SN74HC595N" ], results.map(&:mpn)
      token_request, search_request = requests
      assert_includes token_request.body, "grant_type=client_credentials"
      assert_equal "Bearer app-token", search_request["Authorization"]
      assert_equal "cid", search_request["X-DIGIKEY-Client-Id"]
      assert_equal "SN74HC595N", JSON.parse(search_request.body)["Keywords"]
    end
  end

  test "search failures read as the user can act on them" do
    {
      [ 401, "" ] => /credentials/i,
      [ 500, "oops" ] => /DigiKey API returned 500/,
      [ 200, "<html>" ] => /unreadable|could not read/i,
      [ Errno::ECONNREFUSED.new, nil ] => /Could not reach DigiKey/
    }.each do |response, message|
      with_fake_http(TOKEN, response) do
        error = assert_raises(SupplierCatalog::LookupError) { provider.search("X") }
        assert_match message, error.message
      end
    end
  end

  test "an app token DigiKey refuses or leaves out is reported" do
    { [ 401, "" ] => /credentials/i, [ 200, "{}" ] => /token/i, [ 200, "nope" ] => /token/i }.each do |response, message|
      with_fake_http(response) do
        error = assert_raises(SupplierCatalog::LookupError) { provider.search("X") }
        assert_match message, error.message
      end
    end
  end

  test "an order import sends the account token and reads the order" do
    order = { "SalesOrderId" => 84512345, "LineItems" => [ { "ManufacturerPartNumber" => "SN74HC595N", "DigiKeyPartNumber" => "296-1395-5-ND", "Quantity" => 25, "UnitPrice" => "0.52" } ] }

    with_fake_http([ 200, order.to_json ]) do |requests|
      result = provider(access_token: "user-token").import_order("84512345")

      assert_equal "Bearer user-token", requests.sole["Authorization"]
      assert_match %r{/84512345\z}, requests.sole.path
      assert_equal [ [ "SN74HC595N", 25 ] ], result.lines.map { |line| [ line.mpn, line.quantity ] }
    end
  end

  test "order import failures read as the user can act on them" do
    {
      [ 401, "" ] => /Reconnect your DigiKey account/,
      [ 404, "" ] => /couldn't find that sales order/,
      [ 500, { "detail" => "Server is sad" }.to_json ] => /returned 500 — Server is sad/,
      [ 502, "Bad gateway" ] => /returned 502 — Bad gateway/,
      [ 200, "not json" ] => /unreadable|could not read/i,
      [ SocketError.new("dns"), nil ] => /dns/
    }.each do |response, message|
      with_fake_http(response) do
        error = assert_raises(SupplierCatalog::LookupError) { provider(access_token: "t").import_order("123") }
        assert_match message, error.message
      end
    end
  end

  test "an order import without a connected account sends nothing" do
    with_fake_http do |requests|
      assert_raises(SupplierCatalog::LookupError) { provider.import_order("123") }
      assert_empty requests
    end
  end

  test "an authorization code DigiKey refuses, or an unreadable token reply, is reported" do
    { [ 400, "" ] => /authoriz/i, [ 200, "<html>" ] => /token/i }.each do |response, message|
      with_fake_http(response) do
        error = assert_raises(SupplierCatalog::LookupError) do
          SupplierCatalog::Digikey.exchange_code(client_id: "c", client_secret: "s", code: "x", redirect_uri: "https://app.test/cb")
        end
        assert_match message, error.message
      end
    end
  end
end

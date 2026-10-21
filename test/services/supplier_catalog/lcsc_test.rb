require "test_helper"

class SupplierCatalog::LcscTest < ActiveSupport::TestCase
  # A product as product/query/list returns it (trimmed to the fields we map).
  def list_product(code: "C17414", model: "0805W8F1002T5E", id: 18_062)
    {
      "productId" => id,
      "productCode" => code,
      "productModel" => model,
      "brandNameEn" => "UNI-ROYAL(Uniroyal Elec)",
      "productIntroEn" => "10kΩ ±1% 125mW 0805 Chip Resistor - Surface Mount ROHS",
      "encapStandard" => "0805",
      "isEnvironment" => true,
      "pdfUrl" => "https://datasheet.lcsc.com/datasheet/pdf/84794a12d4f4993a790a768670f430d8.pdf",
      "productImageUrlBig" => "https://assets.lcsc.com/images/lcsc/900x900/20230118_UNI-ROYAL-0805W8F1002T5E_C17414_front.jpg",
      "url" => "https://www.lcsc.com/product-detail/C17414.html",
      "productPriceList" => [
        { "ladder" => 100, "usdPrice" => 0.0011, "productPrice" => "0.0011" },
        { "ladder" => 20, "usdPrice" => 0.0015, "productPrice" => "0.0015" }
      ]
    }
  end

  # The detail record adds the parametric specs.
  def detail_payload(product)
    {
      "code" => 200,
      "result" => product.merge(
        "productNameEn" => "RES 10kΩ ±1% 125mW 0805",
        "paramVOList" => [
          { "paramNameEn" => "Resistance", "paramValueEn" => "10kΩ" },
          { "paramNameEn" => "Tolerance", "paramValueEn" => "±1%" },
          { "paramNameEn" => "Power(Watts)", "paramValueEn" => "125mW" },
          { "paramNameEn" => "Temperature Coefficient", "paramValueEn" => "-" }
        ]
      )
    }
  end

  def list_payload(products)
    { "code" => 200, "msg" => nil, "result" => { "totalRow" => products.size, "dataList" => products } }
  end

  # Stubs the HTTP boundary: +responses+ maps a path to a payload, or to a
  # lambda of the request. Requests are recorded on the provider.
  def build_provider(responses, currency: "EUR")
    provider = SupplierCatalog::Lcsc.new(currency: currency)
    requests = []
    provider.define_singleton_method(:requests) { requests }
    provider.define_singleton_method(:perform_request) do |method, path, query: nil, body: nil|
      requests << { method: method, path: path, query: query, body: body }
      response = responses.fetch(path)
      response.respond_to?(:call) ? response.call(query: query, body: body) : response
    end
    provider
  end

  test "maps a listed product merged with its detail onto normalized part attributes" do
    product = list_product
    provider = build_provider({ "product/query/list" => list_payload([ product ]), "product/detail" => detail_payload(product) })

    result = provider.search("0805W8F1002T5E").first

    assert_equal "RES 10kΩ ±1% 125mW 0805", result.name
    assert_equal "0805W8F1002T5E", result.mpn
    assert_equal "UNI-ROYAL(Uniroyal Elec)", result.manufacturer
    assert_equal "10kΩ ±1% 125mW 0805 Chip Resistor - Surface Mount ROHS", result.description
    assert_equal "10kΩ", result.value
    assert_equal "0805", result.package_type
    assert_equal "±1%", result.tolerance
    assert_equal "125mW", result.power_rating
    assert_equal "C17414", result.supplier_sku
    assert_equal "https://www.lcsc.com/product-detail/C17414.html", result.product_url
    assert_equal product["pdfUrl"], result.datasheet_url
    assert_equal product["productImageUrlBig"], result.image_url
    assert_equal "lcsc", result.provider
    assert result.rohs_compliant
    refute_includes result.attributes.map { |a| a[:name] }, "Temperature Coefficient", "an empty spec (\"-\") is dropped"
    assert_equal({ productCode: "C17414", productId: 18_062 }, provider.requests.last[:query])
  end

  test "only fills the unit price when the organization works in US dollars" do
    product = list_product
    responses = { "product/query/list" => list_payload([ product ]), "product/detail" => detail_payload(product) }

    assert_equal "0.0015", build_provider(responses, currency: "USD").search("x").first.unit_price

    eur = build_provider(responses, currency: "EUR").search("x").first
    assert_nil eur.unit_price
    assert_includes eur.attributes, { name: "Unit price (USD)", value: "0.0015" }
  end

  test "a code search keeps only the exact product, not codes that start with it" do
    exact = list_product(code: "C2040", id: 1)
    longer = list_product(code: "C20401", id: 2)
    provider = build_provider({ "product/query/list" => list_payload([ longer, exact ]), "product/detail" => ->(**) { detail_payload(exact) } })

    results = provider.search("c2040")

    assert_equal [ "C2040" ], results.map(&:supplier_sku)
  end

  test "exact part number matches come first" do
    variant = list_product(code: "C1", model: "NE555DR-VARIANT", id: 1)
    exact = list_product(code: "C2", model: "NE555DR", id: 2)
    provider = build_provider({ "product/query/list" => list_payload([ variant, exact ]), "product/detail" => { "code" => 405, "msg" => "This product does not exist." } })

    assert_equal %w[NE555DR NE555DR-VARIANT], provider.search("ne555dr").map(&:mpn)
  end

  test "keeps the listed data when the detail request fails" do
    product = list_product
    provider = build_provider({
      "product/query/list" => list_payload([ product ]),
      "product/detail" => ->(**) { raise SupplierCatalog::LookupError, "LCSC refused the search (HTTP 403)." }
    })

    result = provider.search("0805W8F1002T5E").first

    assert_equal "0805W8F1002T5E", result.mpn
    # No specs: recovered from the description instead.
    assert_equal "10kΩ", result.value
    assert_equal "1%", result.tolerance
  end

  test "fetches the detail of the first few results only" do
    products = (1..5).map { |i| list_product(code: "C#{i}", model: "PART-#{i}", id: i) }
    provider = build_provider({ "product/query/list" => list_payload(products), "product/detail" => ->(query:, **) { detail_payload(products.find { |p| p["productCode"] == query[:productCode] }) } })

    assert_equal 5, provider.search("part").size
    assert_equal SupplierCatalog::Lcsc::MAX_DETAILS, provider.requests.count { |r| r[:path] == "product/detail" }
  end

  test "returns an empty list when nothing matches" do
    provider = build_provider({ "product/query/list" => list_payload([]) })
    assert_empty provider.search("NOPE-123")
  end

  test "strips characters LCSC's firewall rejects from the query" do
    provider = build_provider({ "product/query/list" => list_payload([]) })
    provider.search("<script>NE555'; ")
    assert_equal "script NE555", provider.requests.first[:body][:keyword]

    blank = build_provider({})
    assert_empty blank.search(" <'> ")
    assert_empty blank.requests
  end

  test "an error code in the body raises a LookupError with LCSC's message" do
    provider = build_provider({ "product/query/list" => { "code" => 405, "msg" => "Product search error.", "result" => nil } })

    error = assert_raises(SupplierCatalog::LookupError) { provider.search("x") }
    assert_match(/Product search error/, error.message)
  end

  test "a refused or unreadable response raises an actionable LookupError" do
    provider = SupplierCatalog::Lcsc.new
    forbidden = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    http = Object.new
    http.define_singleton_method(:method_missing) { |*| nil }
    http.define_singleton_method(:respond_to_missing?) { |*| true }
    http.define_singleton_method(:request) { |_req| forbidden }

    stub_singleton(Net::HTTP, :new, ->(*) { http }) do
      error = assert_raises(SupplierCatalog::LookupError) { provider.search("x") }
      assert_match(/HTTP 403/, error.message)
    end

    garbled = Net::HTTPOK.new("1.1", "200", "OK")
    garbled.instance_variable_set(:@read, true)
    garbled.instance_variable_set(:@body, "<html>not json</html>")
    http.define_singleton_method(:request) { |_req| garbled }

    stub_singleton(Net::HTTP, :new, ->(*) { http }) do
      error = assert_raises(SupplierCatalog::LookupError) { provider.search("x") }
      assert_match(/unreadable/, error.message)
    end
  end

  test "a network failure becomes a LookupError" do
    provider = SupplierCatalog::Lcsc.new
    stub_singleton(Net::HTTP, :new, ->(*) { raise SocketError, "getaddrinfo failed" }) do
      error = assert_raises(SupplierCatalog::LookupError) { provider.search("x") }
      assert_match(/Could not reach LCSC/, error.message)
    end
  end
end

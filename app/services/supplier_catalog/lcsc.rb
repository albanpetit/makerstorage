# frozen_string_literal: true

require "net/http"
require "json"

module SupplierCatalog
  # LCSC Electronics provider, through the JSON endpoints behind lcsc.com's own
  # product search (wmsc.lcsc.com). LCSC's official API is only granted to
  # approved partners, so this uses the public, keyless endpoints instead: they
  # aren't a supported API and may change or block us without notice, which is
  # why the integration is opt-in (Organization#lcsc_enabled) and every failure
  # surfaces as a LookupError rather than breaking the lookup.
  #
  # A search lists matching products (by MPN, LCSC code "C2040", or keywords),
  # then fetches the full product detail of the first few for their parametric
  # specs, which the list leaves out.
  class Lcsc
    BASE_URL = "https://wmsc.lcsc.com/ftps/wm"
    PRODUCT_PAGE_URL = "https://www.lcsc.com/product-detail/%s.html"
    MAX_RECORDS = 10
    # Detail requests per search (one each): enough for the exact match and a
    # couple of variants without hammering an endpoint we use as a guest.
    MAX_DETAILS = 3
    PROVIDER = "lcsc"
    # LCSC prices are always in US dollars, whatever the site's currency switch shows.
    PRICE_CURRENCY = "USD"

    # LCSC codes look like "C2040".
    LCSC_CODE = /\AC\d+\z/i

    # LCSC's WAF answers an HTML 403 to anything resembling markup or SQL, so
    # those characters are dropped from the query (part numbers never need them).
    UNSAFE_QUERY_CHARS = /[<>'";\\`]|[[:cntrl:]]/

    # Candidate LCSC spec names (paramNameEn) per Part field, first match wins
    # (case-insensitive).
    ATTRIBUTE_MAP = {
      value: [ "Resistance", "Capacitance", "Inductance" ],
      tolerance: [ "Tolerance" ],
      voltage_rating: [ "Voltage Rating", "Voltage Rated", "Rated Voltage", "Voltage - Rated", "Voltage Rating - DC" ],
      power_rating: [ "Power(Watts)", "Power (Watts)", "Power Rating", "Power" ]
    }.freeze

    # +currency+ is the organization's: LCSC's USD price only pre-fills the
    # part's unit price when they match.
    def initialize(currency: nil)
      @currency = currency
    end

    # Returns Array<PartResult> for +query+ (may be empty). Raises LookupError.
    def search(query)
      keyword = sanitize(query)
      return [] if keyword.blank?

      products = list_products(keyword)
      # A code search also lists codes that merely start with it (C2040 → C20401),
      # so keep only the exact product when it's there.
      if keyword.match?(LCSC_CODE)
        exact = products.select { |product| product["productCode"].to_s.casecmp?(keyword) }
        products = exact if exact.any?
      end
      products = rank(products, keyword).first(MAX_RECORDS)

      products.each_with_index.map do |product, index|
        build_result(index < MAX_DETAILS ? with_details(product) : product)
      end
    end

    private

    def sanitize(query)
      query.to_s.gsub(UNSAFE_QUERY_CHARS, " ").squish.first(100)
    end

    # Exact MPN or LCSC code matches first, then LCSC's own order.
    def rank(products, keyword)
      products.each_with_index.sort_by do |product, index|
        exact = product["productModel"].to_s.casecmp?(keyword) || product["productCode"].to_s.casecmp?(keyword)
        [ exact ? 0 : 1, index ]
      end.map(&:first)
    end

    def list_products(keyword)
      payload = perform_request(:post, "product/query/list", body: {
        keyword: keyword,
        catalogIdList: [], brandIdList: [], encapValueList: [], productArrangeList: [],
        paramNameValueMap: {},
        isStock: false, isOtherSuppliers: false, isAsianBrand: false, isDeals: false, isEnvironment: false,
        currentPage: 1,
        pageSize: MAX_RECORDS
      })
      check_for_errors!(payload)
      Array(payload.dig("result", "dataList"))
    end

    # The product merged with its detail record (specs, full description). A
    # failed detail request keeps the list data rather than failing the search.
    def with_details(product)
      return product if product["productCode"].blank? || product["productId"].blank?

      payload = perform_request(:get, "product/detail", query: {
        productCode: product["productCode"], productId: product["productId"]
      })
      return product unless payload["code"].to_i == 200 && payload["result"].is_a?(Hash)

      product.merge(payload["result"].compact)
    rescue LookupError
      product
    end

    # Isolated HTTP boundary — stubbed in tests. Returns the parsed JSON Hash.
    # LCSC answers HTTP 200 with a code in the body for its own errors; another
    # status means the request itself was refused (WAF) or the endpoint moved.
    def perform_request(method, path, query: nil, body: nil)
      uri = URI("#{BASE_URL}/#{path}")
      uri.query = URI.encode_www_form(query) if query

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = (method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri))
      # The endpoints reject requests without a User-Agent.
      request["User-Agent"] = RemoteFile::BROWSER_HEADERS["User-Agent"]
      request["Accept"] = "application/json"
      request["Origin"] = "https://www.lcsc.com"
      request["Referer"] = "https://www.lcsc.com/"
      if body
        request["Content-Type"] = "application/json;charset=UTF-8"
        request.body = body.to_json
      end

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise LookupError, I18n.t("errors.lcsc.refused", code: response.code)
      end

      JSON.parse(response.body)
    rescue *NETWORK_ERRORS => e
      raise LookupError, I18n.t("errors.lcsc.unreachable", error: e.message)
    rescue JSON::ParserError
      raise LookupError, I18n.t("errors.lcsc.unreadable_changed")
    end

    # Every response wraps the data as { code:, msg:, result: }; 200 is success.
    def check_for_errors!(payload)
      raise LookupError, I18n.t("errors.lcsc.unreadable") unless payload.is_a?(Hash)
      return if payload["code"].to_i == 200

      message = payload["msg"].presence || "error #{payload['code']}"
      raise LookupError, I18n.t("errors.lcsc.failed", error: message)
    end

    def build_result(product)
      params = Array(product["paramVOList"]).filter_map do |param|
        name = param["paramNameEn"].to_s.strip
        value = param["paramValueEn"].to_s.strip
        { name: name, value: value } if name.present? && value.present? && value != "-"
      end
      description = (product["productIntroEn"].presence || product["productDescEn"].presence).to_s.strip
      parsed = DescriptionParser.parse(description)
      price = first_price(product["productPriceList"])
      code = product["productCode"].presence

      PartResult.new(
        name: (product["productNameEn"].presence || description).to_s.slice(0, 255).presence,
        mpn: product["productModel"].presence,
        manufacturer: product["brandNameEn"].presence,
        description: description.presence,
        value: attribute_value(params, :value) || parsed[:value],
        package_type: product["encapStandard"].presence || parsed[:package_type],
        tolerance: attribute_value(params, :tolerance) || parsed[:tolerance],
        voltage_rating: attribute_value(params, :voltage_rating) || parsed[:voltage_rating],
        power_rating: attribute_value(params, :power_rating) || parsed[:power_rating],
        unit_price: (price if @currency == PRICE_CURRENCY),
        price_breaks: (@currency == PRICE_CURRENCY ? price_breaks(product["productPriceList"]) : []),
        rohs_compliant: product["isEnvironment"] == true,
        datasheet_url: product["pdfUrl"].presence,
        image_url: (product["productImageUrlBig"].presence || Array(product["productImages"]).first.presence),
        product_url: product["url"].presence || (code && format(PRODUCT_PAGE_URL, code)),
        supplier_sku: code,
        provider: PROVIDER,
        attributes: params + (price ? [ { name: "Unit price (USD)", value: price } ] : [])
      )
    end

    # First present value among the candidate spec names for +field+.
    def attribute_value(params, field)
      names = ATTRIBUTE_MAP.fetch(field)
      params.find { |param| names.any? { |candidate| candidate.casecmp?(param[:name]) } }&.dig(:value)
    end

    # Every ladder step as { quantity:, unit_price: }, by quantity.
    def price_breaks(price_list)
      Array(price_list).filter_map do |entry|
        quantity = entry["ladder"].to_i
        price = Float((entry["usdPrice"] || entry["productPrice"]).to_s, exception: false)
        { quantity: quantity, unit_price: price.to_s } if quantity.positive? && price
      end.sort_by { |row| row[:quantity] }
    end

    # Smallest-quantity price, as a numeric string.
    def first_price(price_list)
      row = Array(price_list).min_by { |entry| entry["ladder"].to_i }
      return nil unless row

      Float(row["usdPrice"] || row["productPrice"]).to_s
    rescue ArgumentError, TypeError
      nil
    end
  end
end

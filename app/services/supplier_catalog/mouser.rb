# frozen_string_literal: true

require "net/http"
require "json"

module SupplierCatalog
  # Mouser Electronics Search API v1 provider.
  # https://www.mouser.com/api-hub/ — keyword search returns up to +MAX_RECORDS+
  # matches for a manufacturer part number, which we normalize into PartResults.
  class Mouser
    ENDPOINT = "https://api.mouser.com/api/v1/search/keyword"
    # Order/Cart API base (separate key from the Search API). Endpoint shapes
    # follow Mouser's API Hub docs; parsing is deliberately tolerant of key-name
    # variation since these responses can't be exercised without live credentials.
    ORDER_API_BASE = "https://api.mouser.com/api/v1"
    MAX_RECORDS = 10
    PROVIDER = "mouser"

    # Candidate Mouser attribute names per Part field, first match wins
    # (case-insensitive). Naming varies by product family and by the account's
    # sign-up language, so both English and French variants are listed.
    #
    # Note: Mouser's public API usually only returns *packaging* attributes
    # (Conditionnement / Quantité standard du lot), not the parametric specs.
    # The parametric values are instead embedded in the Description, which
    # DescriptionParser recovers as a fallback.
    ATTRIBUTE_MAP = {
      value: [ "Resistance", "Capacitance", "Inductance", "Value", "Résistance", "Capacité", "Inductance", "Valeur" ],
      package_type: [ "Package / Case", "Supplier Device Package", "Mounting Style", "Boîtier", "Boitier", "Type de boîtier", "Package / Boîtier" ],
      tolerance: [ "Tolerance", "Tolérance" ],
      voltage_rating: [ "Voltage Rating", "Voltage Rating - DC", "Voltage - Rated", "Voltage Rating (Vdc)", "Tension nominale", "Tension assignée", "Tension" ],
      power_rating: [ "Power (Watts)", "Power Rating", "Power - Max", "Puissance", "Puissance nominale", "Puissance (Watts)" ]
    }.freeze

    def initialize(api_key:, order_api_key: nil)
      @api_key = api_key
      @order_api_key = order_api_key
    end

    # Fetches a placed Mouser order by its web order number and normalizes it to
    # a SupplierCatalog::OrderResult. Raises LookupError on failure.
    def import_order(order_number)
      payload = order_request(:get, "orderhistory/ByWebOrderNumber", query: { webOrderNumber: order_number.to_s.strip })
      check_for_errors!(payload)
      build_order_result(payload, order_number)
    end

    # Builds a cart at Mouser from +items+ (each { supplier_sku:, quantity: }) and
    # returns a SupplierCatalog::CartResult with live pricing/availability. Raises
    # LookupError on failure.
    def create_cart(items, currency: "EUR")
      body = {
        CurrencyCode: currency,
        CartItems: items.map { |item| { MouserPartNumber: item[:supplier_sku], Quantity: item[:quantity] } }
      }
      payload = order_request(:post, "cart", body: body)
      check_for_errors!(payload)
      build_cart_result(payload)
    end

    # Returns Array<PartResult> for +mpn+ (may be empty). Raises LookupError.
    def search(mpn)
      body = {
        SearchByKeywordRequest: {
          keyword: mpn.to_s.strip,
          records: MAX_RECORDS,
          startingRecord: 0,
          searchOptions: "",
          searchWithYourSignUpLanguage: ""
        }
      }

      payload = perform_request(body)
      check_for_errors!(payload)

      parts = payload.dig("SearchResults", "Parts") || []
      parts.map { |part| build_result(part) }
    end

    private

    # Isolated HTTP boundary — stubbed in tests. Returns the parsed JSON Hash.
    def perform_request(body)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(apiKey: @api_key)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise LookupError, "Mouser API returned #{response.code}"
      end

      JSON.parse(response.body)
    rescue *NETWORK_ERRORS => e
      raise LookupError, "Could not reach Mouser API: #{e.message}"
    rescue JSON::ParserError
      raise LookupError, "Mouser API returned an unreadable response"
    end

    # Mouser reports auth/quota problems in an Errors array (often with HTTP 200).
    def check_for_errors!(payload)
      errors = payload["Errors"]
      return if errors.blank?

      # An invalid/unrecognized key comes back as an "API Key" property error;
      # translate it into something the user can act on rather than Mouser's
      # opaque "Invalid unique identifier." text.
      if errors.any? { |e| e["PropertyName"].to_s.casecmp?("API Key") || e["ResourceKey"] == "InvalidIdentifier" }
        raise LookupError, "Mouser rejected the API key. Check it in Settings → Integrations (it must be a Search API key)."
      end

      messages = errors.filter_map { |e| e["Message"].presence }.join("; ")
      raise LookupError, messages.presence || "Mouser API returned an error"
    end

    def build_result(part)
      attributes = Array(part["ProductAttributes"])
      description = part["Description"].to_s
      # Description is the fallback source for parametric fields Mouser doesn't
      # expose as structured attributes.
      parsed = DescriptionParser.parse(description)

      PartResult.new(
        name: description.slice(0, 255).presence,
        mpn: part["ManufacturerPartNumber"].presence,
        manufacturer: part["Manufacturer"].presence,
        description: description.presence,
        value: attribute_value(attributes, :value) || parsed[:value],
        package_type: attribute_value(attributes, :package_type) || parsed[:package_type],
        tolerance: attribute_value(attributes, :tolerance) || parsed[:tolerance],
        voltage_rating: attribute_value(attributes, :voltage_rating) || parsed[:voltage_rating],
        power_rating: attribute_value(attributes, :power_rating) || parsed[:power_rating],
        unit_price: first_price(part["PriceBreaks"]),
        rohs_compliant: rohs?(part["ROHSStatus"]),
        datasheet_url: part["DataSheetUrl"].presence,
        image_url: (part["ImagePath"] || part["ImageURL"]).presence,
        product_url: part["ProductDetailUrl"].presence,
        supplier_sku: part["MouserPartNumber"].presence,
        provider: PROVIDER,
        attributes: attributes.map { |a| { name: a["AttributeName"], value: a["AttributeValue"] } }
      )
    end

    # First present value among the candidate attribute names for +field+.
    def attribute_value(attributes, field)
      names = ATTRIBUTE_MAP.fetch(field)
      attributes.each do |attr|
        name = attr["AttributeName"].to_s
        next unless names.any? { |candidate| candidate.casecmp?(name) }

        value = attr["AttributeValue"].to_s.strip
        return value if value.present?
      end
      nil
    end

    # Lowest-quantity price break, parsed to a numeric string.
    def first_price(price_breaks)
      break_row = Array(price_breaks).min_by { |b| b["Quantity"].to_i }
      numeric_price(break_row&.dig("Price"))
    end

    # Normalizes a Mouser price string to a numeric string (strips currency
    # symbols/thousands separators, normalizes decimal comma). Returns nil when
    # unparseable.
    def numeric_price(raw)
      return nil if raw.blank?

      digits = raw.to_s.gsub(/[^0-9.,]/, "")
      # If both separators appear, assume the last one is the decimal separator.
      if digits.include?(",") && digits.include?(".")
        digits = digits.rindex(",") > digits.rindex(".") ? digits.delete(".").tr(",", ".") : digits.delete(",")
      elsif digits.include?(",")
        digits = digits.tr(",", ".")
      end

      Float(digits).to_s
    rescue ArgumentError
      nil
    end

    # Isolated HTTP boundary for the Order/Cart API — stubbed in tests. Returns
    # the parsed JSON Hash. The order key is passed as an apiKey query param, the
    # same way the Search API authenticates.
    def order_request(method, path, query: {}, body: nil)
      raise LookupError, "No Mouser Order API key is configured." if @order_api_key.blank?

      uri = URI("#{ORDER_API_BASE}/#{path}")
      uri.query = URI.encode_www_form({ apiKey: @order_api_key }.merge(query))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 15

      request = (method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri))
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = body.to_json if body

      response = http.request(request)

      raise LookupError, "Mouser Order API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue *NETWORK_ERRORS => e
      raise LookupError, "Could not reach Mouser Order API: #{e.message}"
    rescue JSON::ParserError
      raise LookupError, "Mouser Order API returned an unreadable response"
    end

    def build_order_result(payload, requested_number)
      summary = payload["SummaryDetail"] || {}
      raw_lines = payload["OrderLines"] || payload["MouserOrderLines"] || summary["OrderLines"] || []

      SupplierCatalog::OrderResult.new(
        order_number: (payload["WebOrderNumber"] || payload["OrderNumber"] || requested_number).to_s,
        status: payload["OrderStatusDisplay"] || payload["Status"] || summary["OrderStatusDisplay"],
        placed_at: payload["OrderDate"] || payload["DateCreated"] || summary["OrderDate"],
        total: numeric_price(payload["MerchandiseTotal"] || summary["MerchandiseTotal"]),
        currency: payload["CurrencyCode"] || payload["Currency"],
        lines: Array(raw_lines).map { |line| build_order_line(line) }
      )
    end

    def build_cart_result(payload)
      raw_lines = payload["CartItems"] || payload["MouserCartItems"] || []

      SupplierCatalog::CartResult.new(
        cart_key: payload["CartKey"] || payload["ID"],
        checkout_url: payload["CheckoutUrl"].presence,
        currency: payload["CurrencyCode"] || payload["Currency"],
        merchandise_total: numeric_price(payload["MerchandiseTotal"]),
        lines: Array(raw_lines).map { |line| build_order_line(line) }
      )
    end

    def build_order_line(line)
      SupplierCatalog::OrderLineResult.new(
        mpn: line["MfrPartNumber"] || line["ManufacturerPartNumber"],
        manufacturer: line["Manufacturer"],
        supplier_sku: line["MouserPartNumber"] || line["MouserPN"],
        description: line["Description"],
        quantity: (line["Quantity"] || line["OrderQuantity"]).to_i,
        unit_price: numeric_price(line["UnitPrice"] || line["Price"])
      )
    end

    def rohs?(status)
      status.to_s.downcase.include?("rohs") && !status.to_s.downcase.include?("non")
    end
  end
end

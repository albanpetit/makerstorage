# frozen_string_literal: true

require "net/http"
require "json"
require "digest"

module SupplierCatalog
  # DigiKey Product Information API v4 provider.
  # https://developer.digikey.com/products/product-information-v4
  #
  # DigiKey uses OAuth2 client-credentials: a Client ID + Client Secret are
  # exchanged for a short-lived bearer token (cached, ~10 min) which authorizes
  # the keyword search. Results are normalized into PartResults.
  class Digikey
    TOKEN_ENDPOINT = "https://api.digikey.com/v1/oauth2/token"
    SEARCH_ENDPOINT = "https://api.digikey.com/products/v4/search/keyword"
    MAX_RECORDS = 10
    PROVIDER = "digikey"

    # DigiKey returns rich structured Parameters (ParameterText / ValueText), so
    # unlike Mouser these usually carry the parametric specs directly. First
    # match wins (case-insensitive); DescriptionParser is a fallback.
    ATTRIBUTE_MAP = {
      value: [ "Resistance", "Capacitance", "Inductance" ],
      package_type: [ "Package / Case", "Supplier Device Package", "Mounting Type" ],
      tolerance: [ "Tolerance" ],
      voltage_rating: [ "Voltage - Rated", "Voltage Rating - DC", "Voltage - Rated (DC)", "Voltage Rating" ],
      power_rating: [ "Power (Watts)", "Power - Max" ]
    }.freeze

    def initialize(client_id:, client_secret:)
      @client_id = client_id
      @client_secret = client_secret
    end

    # Returns Array<PartResult> for +mpn+ (may be empty). Raises LookupError.
    def search(mpn)
      body = { "Keywords" => mpn.to_s.strip, "Limit" => MAX_RECORDS, "Offset" => 0 }

      payload = perform_request(body)
      products = payload["Products"] || []
      products.map { |product| build_result(product) }
    end

    private

    # Isolated HTTP boundary for the keyword search — stubbed in tests. Returns
    # the parsed JSON Hash. Fetches (and caches) the OAuth token first.
    def perform_request(body)
      uri = URI(SEARCH_ENDPOINT)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["X-DIGIKEY-Client-Id"] = @client_id
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["X-DIGIKEY-Locale-Site"] = "US"
      request["X-DIGIKEY-Locale-Language"] = "en"
      request["X-DIGIKEY-Locale-Currency"] = "USD"
      request.body = body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise LookupError, search_error_message(response)
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise LookupError, "Could not reach DigiKey API: #{e.message}"
    rescue JSON::ParserError
      raise LookupError, "DigiKey API returned an unreadable response"
    end

    # A 401 on the search means the token was rejected (usually bad/unapproved
    # credentials); everything else is passed through with the status code.
    def search_error_message(response)
      if response.is_a?(Net::HTTPUnauthorized)
        "DigiKey rejected the credentials. Check the Client ID and Secret in Settings → Integrations."
      else
        "DigiKey API returned #{response.code}"
      end
    end

    # Bearer token from the client-credentials grant, cached across lookups for
    # slightly less than DigiKey's ~10 min token lifetime.
    def access_token
      Rails.cache.fetch("supplier_catalog:digikey:token:#{token_cache_key}", expires_in: 9.minutes) do
        request_token
      end
    end

    def token_cache_key
      Digest::SHA256.hexdigest(@client_id.to_s)
    end

    def request_token
      uri = URI(TOKEN_ENDPOINT)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request.set_form_data(
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret
      )

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise LookupError, "DigiKey rejected the credentials. Check the Client ID and Secret in Settings → Integrations."
      end

      token = JSON.parse(response.body)["access_token"]
      raise LookupError, "DigiKey did not return an access token." if token.blank?

      token
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise LookupError, "Could not reach DigiKey API: #{e.message}"
    rescue JSON::ParserError
      raise LookupError, "DigiKey API returned an unreadable token response"
    end

    def build_result(product)
      description = product.dig("Description", "ProductDescription").to_s
      detailed = product.dig("Description", "DetailedDescription").to_s
      parameters = Array(product["Parameters"])
      # Structured parameters are primary; the description is a fallback for
      # anything they don't carry.
      parsed = DescriptionParser.parse([ description, detailed ].join(" ").strip)

      PartResult.new(
        name: description.slice(0, 255).presence,
        mpn: product["ManufacturerProductNumber"].presence,
        manufacturer: product.dig("Manufacturer", "Name").presence,
        description: description.presence,
        value: parameter_value(parameters, :value) || parsed[:value],
        package_type: parameter_value(parameters, :package_type) || parsed[:package_type],
        tolerance: parameter_value(parameters, :tolerance) || parsed[:tolerance],
        voltage_rating: parameter_value(parameters, :voltage_rating) || parsed[:voltage_rating],
        power_rating: parameter_value(parameters, :power_rating) || parsed[:power_rating],
        unit_price: unit_price(product),
        rohs_compliant: rohs?(product.dig("Classifications", "RohsStatus")),
        datasheet_url: product["DatasheetUrl"].presence,
        image_url: product["PhotoUrl"].presence,
        product_url: product["ProductUrl"].presence,
        supplier_sku: digikey_product_number(product),
        provider: PROVIDER,
        attributes: parameters.map { |p| { name: p["ParameterText"], value: p["ValueText"] } }
      )
    end

    # First present value among the candidate parameter names for +field+.
    # DigiKey uses "-" for an unspecified parameter, which we treat as blank.
    def parameter_value(parameters, field)
      names = ATTRIBUTE_MAP.fetch(field)
      parameters.each do |param|
        name = param["ParameterText"].to_s
        next unless names.any? { |candidate| candidate.casecmp?(name) }

        value = param["ValueText"].to_s.strip
        return value if value.present? && value != "-"
      end
      nil
    end

    # Prefer the product's headline UnitPrice; fall back to the lowest-quantity
    # standard price break across variations.
    def unit_price(product)
      raw = product["UnitPrice"]
      raw = lowest_break_price(product) if raw.blank? || raw.to_f.zero?
      return nil if raw.blank?

      Float(raw).to_s
    rescue ArgumentError
      nil
    end

    def lowest_break_price(product)
      breaks = Array(product["ProductVariations"]).flat_map { |v| Array(v["StandardPricing"]) }
      breaks.reject { |b| b["UnitPrice"].blank? }
            .min_by { |b| b["BreakQuantity"].to_i }
            &.dig("UnitPrice")
    end

    # DigiKey's own ordering SKU lives on the product variations (e.g. cut tape
    # vs reel); the first one is a reasonable default.
    def digikey_product_number(product)
      Array(product["ProductVariations"]).filter_map { |v| v["DigiKeyProductNumber"].presence }.first
    end

    def rohs?(status)
      text = status.to_s.downcase
      text.include?("rohs") && !text.include?("non")
    end
  end
end

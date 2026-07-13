# frozen_string_literal: true

require "net/http"
require "json"

module SupplierCatalog
  # Mouser Electronics Search API v1 provider.
  # https://www.mouser.com/api-hub/ — keyword search returns up to +MAX_RECORDS+
  # matches for a manufacturer part number, which we normalize into PartResults.
  class Mouser
    ENDPOINT = "https://api.mouser.com/api/v1/search/keyword"
    MAX_RECORDS = 10
    PROVIDER = "mouser"

    # Candidate Mouser attribute names per Part field, first match wins
    # (case-insensitive). Naming varies by product family and by the account's
    # sign-up language, so both English and French variants are listed.
    #
    # Note: Mouser's public API usually only returns *packaging* attributes
    # (Conditionnement / Quantité standard du lot), not the parametric specs.
    # The parametric values are instead embedded in the Description, which
    # #parse_description recovers as a fallback (see PARAMETRIC_PATTERNS).
    ATTRIBUTE_MAP = {
      value: [ "Resistance", "Capacitance", "Inductance", "Value", "Résistance", "Capacité", "Inductance", "Valeur" ],
      package_type: [ "Package / Case", "Supplier Device Package", "Mounting Style", "Boîtier", "Boitier", "Type de boîtier", "Package / Boîtier" ],
      tolerance: [ "Tolerance", "Tolérance" ],
      voltage_rating: [ "Voltage Rating", "Voltage Rating - DC", "Voltage - Rated", "Voltage Rating (Vdc)", "Tension nominale", "Tension assignée", "Tension" ],
      power_rating: [ "Power (Watts)", "Power Rating", "Power - Max", "Puissance", "Puissance nominale", "Puissance (Watts)" ]
    }.freeze

    # Whitelisted SMD chip sizes — matched as exact tokens so a stray "1000"
    # never reads as a package.
    SMD_SIZES = %w[0201 0402 0603 0805 1206 1210 1218 1812 2010 2220 2512 2920].freeze

    # Common through-hole/SMD package families, optionally suffixed with a pin count.
    PACKAGE_FAMILY = /\b(?:SOT|SOD|SOIC|SO|TSSOP|VSSOP|MSOP|SSOP|QSOP|TSOP|QFN|DFN|VQFN|WQFN|QFP|TQFP|LQFP|BGA|LGA|WLCSP|DIP|PDIP|SIP|TO|DPAK|D2PAK|SMA|SMB|SMC|MELF)-?\d*[A-Z]?\b/i

    # Parametric values embedded in the Description, recovered per field. Order
    # inside a field doesn't matter; the first match in the text is used.
    PARAMETRIC_PATTERNS = {
      value: /\b\d+(?:[.,]\d+)?\s?[kKMmµuµnpGT]?(?:Ohms?|Ω|F|H)\b/i,
      tolerance: /(?<![\/\d])\b\d+(?:[.,]\d+)?\s?%/,
      power_rating: %r{\b\d+(?:[./]\d+)?\s?[mµu]?W\b}i,
      voltage_rating: /\b\d+(?:[.,]\d+)?\s?V(?:DC|AC)?\b/i
    }.freeze

    def initialize(api_key:)
      @api_key = api_key
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
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
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
      parsed = parse_description(description)

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

    # Recovers parametric fields from the free-text Description. Conservative:
    # each pattern requires a unit (Ω/F/H, %, W, V) or a known package token, so
    # non-passive descriptions (e.g. an EEPROM) simply yield nothing rather than
    # a wrong guess.
    def parse_description(text)
      return {} if text.blank?

      result = { package_type: extract_package(text) }
      PARAMETRIC_PATTERNS.each do |field, pattern|
        match = text[pattern]
        result[field] = match.strip if match
      end
      result
    end

    def extract_package(text)
      SMD_SIZES.find { |size| text.match?(/(?<!\d)#{size}(?!\d)/) } || text[PACKAGE_FAMILY]
    end

    # Lowest-quantity price break, parsed to a numeric string (strips currency
    # symbols/thousands separators, normalizes decimal comma).
    def first_price(price_breaks)
      break_row = Array(price_breaks).min_by { |b| b["Quantity"].to_i }
      raw = break_row&.dig("Price")
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

    def rohs?(status)
      status.to_s.downcase.include?("rohs") && !status.to_s.downcase.include?("non")
    end
  end
end

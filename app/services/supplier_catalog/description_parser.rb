# frozen_string_literal: true

module SupplierCatalog
  # Recovers parametric fields (value / package / tolerance / power / voltage)
  # from a component's free-text description. Shared by providers as a fallback
  # for fields their structured attributes don't expose.
  #
  # Conservative by design: every pattern requires a unit (Ω/F/H, %, W, V) or a
  # known package token, so a non-passive description (e.g. an EEPROM) yields
  # nothing rather than a wrong guess.
  module DescriptionParser
    module_function

    # Whitelisted SMD chip sizes — matched as exact tokens so a stray "1000"
    # never reads as a package.
    SMD_SIZES = %w[0201 0402 0603 0805 1206 1210 1218 1812 2010 2220 2512 2920].freeze

    # Common through-hole/SMD package families, optionally suffixed with a pin count.
    PACKAGE_FAMILY = /\b(?:SOT|SOD|SOIC|SO|TSSOP|VSSOP|MSOP|SSOP|QSOP|TSOP|QFN|DFN|VQFN|WQFN|QFP|TQFP|LQFP|BGA|LGA|WLCSP|DIP|PDIP|SIP|TO|DPAK|D2PAK|SMA|SMB|SMC|MELF)-?\d*[A-Z]?\b/i

    # Parametric values embedded in the description, recovered per field. Order
    # inside a field doesn't matter; the first match in the text is used.
    PARAMETRIC_PATTERNS = {
      value: /\b\d+(?:[.,]\d+)?\s?[kKMmµuµnpGT]?(?:Ohms?|Ω|F|H)\b/i,
      tolerance: /(?<![\/\d])\b\d+(?:[.,]\d+)?\s?%/,
      power_rating: %r{\b\d+(?:[./]\d+)?\s?[mµu]?W\b}i,
      voltage_rating: /\b\d+(?:[.,]\d+)?\s?V(?:DC|AC)?\b/i
    }.freeze

    # Returns a Hash of the fields it could recover from +text+ (package_type
    # may be nil; parametric keys are only present when matched).
    def parse(text)
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
  end
end

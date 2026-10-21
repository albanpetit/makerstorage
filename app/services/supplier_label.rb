# frozen_string_literal: true

# Reads the 2D code printed on a distributor's bag label into the fields the
# scanner needs to find (or create) the part and receive the bag.
#
# Two formats are understood:
# - ECIA / ISO/IEC 15434 "format 06" DataMatrix (DigiKey, Mouser, and most
#   ECIA-compliant distributors): `[)>` RS `06` GS field GS field … RS EOT, each
#   field an ANSI MH10.8.2 data identifier followed by its value (`1P` MPN,
#   `Q` quantity, `1K` sales order, …).
# - LCSC's QR code: `{pbn:PICK…,on:WM…,pc:C2040,pm:RP2040,qty:10,…}`.
#
# Hardware scanners in keyboard mode often can't type the GS/RS control
# characters, so the common printable stand-ins they're configured to send
# (`{GS}`, `<GS>`, `^]`, the ␝ control picture) are accepted too.
class SupplierLabel
  ECIA_HEADER = "[)>"
  GS = "\u001D"
  RS = "\u001E"
  EOT = "\u0004"
  SEPARATOR_STAND_INS = {
    GS => [ "{GS}", "<GS>", "^]", "␝" ],
    RS => [ "{RS}", "<RS>", "^^", "␞" ],
    EOT => [ "{EOT}", "<EOT>", "^D", "␄" ]
  }.freeze

  # Data identifiers (ANSI MH10.8.2) we read, longest first so `30P` and `1P`
  # aren't mistaken for `P`.
  IDENTIFIERS = {
    "30P" => :supplier_sku,
    "1P" => :mpn,
    "P" => :customer_part_number,
    "1V" => :manufacturer,
    "1K" => :sales_order,
    "11K" => :invoice,
    "14K" => :line_item,
    "K" => :purchase_order,
    "Q" => :quantity,
    "1T" => :lot,
    "9D" => :date_code,
    "10D" => :date_code,
    "4L" => :country_of_origin
  }.freeze
  IDENTIFIER_PATTERN = /\A(#{IDENTIFIERS.keys.sort_by { |id| -id.length }.join("|")})(.*)\z/m

  PROVIDER_NAMES = { "digikey" => "DigiKey", "mouser" => "Mouser", "lcsc" => "LCSC" }.freeze

  attr_reader :provider, :mpn, :supplier_sku, :customer_part_number, :manufacturer,
    :quantity, :order_number, :lot, :date_code, :country_of_origin

  # Returns a SupplierLabel, or nil when +raw+ isn't a supplier label (an IPN,
  # a zone code, a plain barcode, …) or carries no part number at all.
  def self.parse(raw)
    text = raw.to_s
    label = if text.include?(ECIA_HEADER)
      parse_ecia(text)
    elsif text.strip.match?(/\A\{.*\bpc:.*\}\z/m)
      parse_lcsc(text.strip)
    end
    label if label&.identifiable?
  end

  def self.parse_ecia(text)
    SEPARATOR_STAND_INS.each { |char, stand_ins| stand_ins.each { |s| text = text.gsub(s, char) } }
    start = text.index("#{ECIA_HEADER}#{RS}06#{GS}")
    return unless start

    body = text[(start + ECIA_HEADER.length + 4)..].split(RS).first.to_s
    fields = {}
    body.split(GS).each do |field|
      match = field.strip.match(IDENTIFIER_PATTERN)
      next unless match

      key = IDENTIFIERS.fetch(match[1])
      fields[key] ||= match[2].strip.presence
    end
    return if fields.empty?

    provider = ecia_provider(fields, body)
    sku = fields[:supplier_sku]
    # DigiKey prints its own part number in the customer part number field when
    # the order line had no customer reference.
    if provider == "digikey" && sku.nil? && fields[:customer_part_number].to_s.end_with?("-ND")
      sku = fields.delete(:customer_part_number)
    end

    new(
      provider: provider,
      mpn: fields[:mpn],
      supplier_sku: sku,
      customer_part_number: fields[:customer_part_number],
      manufacturer: fields[:manufacturer],
      quantity: fields[:quantity],
      order_number: fields[:sales_order] || fields[:invoice] || fields[:purchase_order],
      lot: fields[:lot],
      date_code: fields[:date_code],
      country_of_origin: fields[:country_of_origin]
    )
  end

  # DigiKey labels carry its own part number (`30P`, or a `-ND` suffix) and
  # pick/label ids (`12Z`, `13Z`, `20Z`); Mouser's carry a line item (`14K`)
  # and the manufacturer name (`1V`). Anything else stays a generic ECIA label.
  def self.ecia_provider(fields, body)
    segments = body.split(GS).map(&:strip)
    if fields.key?(:supplier_sku) || fields[:customer_part_number].to_s.end_with?("-ND") ||
        segments.any? { |segment| segment.match?(/\A(12|13|20)Z/) }
      "digikey"
    elsif fields.key?(:line_item) || fields.key?(:manufacturer)
      "mouser"
    end
  end

  def self.parse_lcsc(text)
    fields = text.delete_prefix("{").delete_suffix("}").split(",").filter_map do |pair|
      key, value = pair.split(":", 2)
      [ key.strip, value.to_s.strip.presence ] if key
    end.to_h

    new(
      provider: "lcsc",
      mpn: fields["pm"],
      supplier_sku: fields["pc"],
      quantity: fields["qty"],
      order_number: fields["on"]
    )
  end

  def initialize(provider: nil, mpn: nil, supplier_sku: nil, customer_part_number: nil, manufacturer: nil,
                 quantity: nil, order_number: nil, lot: nil, date_code: nil, country_of_origin: nil)
    @provider = provider
    @mpn = mpn
    @supplier_sku = supplier_sku
    @customer_part_number = customer_part_number
    @manufacturer = manufacturer
    @quantity = quantity.to_s[/\A\d+\z/] ? quantity.to_i : nil
    @quantity = nil if @quantity && (@quantity <= 0 || @quantity > ApplicationRecord::MAX_INTEGER)
    @order_number = order_number
    @lot = lot
    @date_code = date_code
    @country_of_origin = country_of_origin
  end

  def identifiable?
    [ mpn, supplier_sku, customer_part_number ].any?(&:present?)
  end

  def provider_name
    PROVIDER_NAMES.fetch(provider, "Supplier")
  end

  # Stamped on the receipt movement: names the bag's order so the ledger reads
  # "DigiKey 84512345", and lets a second scan of the same bag be spotted.
  def movement_reference
    [ provider_name, order_number.presence || "label" ].join(" ")
  end

  def as_json(*)
    {
      provider: provider,
      provider_name: provider_name,
      mpn: mpn,
      supplier_sku: supplier_sku,
      customer_part_number: customer_part_number,
      manufacturer: manufacturer,
      quantity: quantity,
      order_number: order_number,
      lot: lot,
      date_code: date_code,
      country_of_origin: country_of_origin
    }
  end
end

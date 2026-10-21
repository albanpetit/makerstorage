# Resolves what a scanner read (a typed code, a hardware scanner's keystrokes,
# the in-app camera) to a part or a storage zone of one organization. Shared by
# the Scanner page and stocktake counting, so a label opens the same record
# everywhere.
#
#   lookup = ScanCode.new(current_organization)
#   code = ScanCode.normalize(params[:code])
#   lookup.part(code) || lookup.location(code)
class ScanCode
  # Printed labels fall back to these record-id codes when a part has no IPN,
  # barcode or SKU, or a zone has no code (see app/frontend/lib/labels.ts).
  PART_CODE = /\Apart:(\d+)\z/i
  ZONE_CODE = /\Azone:(\d+)\z/i

  # Label QR codes hold a link to the Scanner page (`https://host/scan?code=MS-00042`)
  # so a phone's own camera app opens the right record. The in-app camera and
  # hardware scanners read that link as plain text: keep only its code, from
  # whichever host printed it.
  def self.normalize(raw)
    code = raw.to_s.strip
    return code unless code.match?(%r{\Ahttps?://}i)

    uri = URI.parse(code)
    return code unless uri.path.to_s.chomp("/").end_with?("/scan")

    URI.decode_www_form(uri.query.to_s).to_h["code"].to_s.strip.presence || code
  rescue URI::InvalidURIError, ArgumentError
    code
  end

  def initialize(organization)
    @organization = organization
  end

  # IPNs are matched first: they are unique per organization and what labels
  # print, whereas an MPN can be shared by several parts.
  def part(code)
    parts = @organization.parts
    if (match = code.match(PART_CODE))
      return parts.find_by(id: match[1])
    end

    downcased = code.downcase
    parts.find_by("LOWER(ipn) = ?", downcased) ||
      parts.where("LOWER(barcode) = :code OR LOWER(sku) = :code OR LOWER(mpn) = :code", code: downcased).first
  end

  def location(code)
    locations = @organization.storage_locations
    if (match = code.match(ZONE_CODE))
      return locations.find_by(id: match[1])
    end

    locations.where("LOWER(code) = ?", code.downcase).first
  end
end

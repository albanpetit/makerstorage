# frozen_string_literal: true

class ScansController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create_movement]

  # Movements created from the scanner page carry this reason so the
  # "Recent scans" feed can be rebuilt from the ledger without a scan table.
  SCANNER_REASON = "Scanner count"
  RECENT_SCANS_LIMIT = 6
  # Printed labels fall back to these record-id codes when a part has no IPN,
  # barcode or SKU, or a zone has no code (see app/frontend/lib/labels.ts).
  PART_CODE = /\Apart:(\d+)\z/i
  ZONE_CODE = /\Azone:(\d+)\z/i
  ZONE_CONTENTS_LIMIT = 50

  def index
    code = normalize_code(params[:code])

    render inertia: "scans/index", props: {
      code: code.presence,
      result: code.present? ? lookup(code) : nil,
      # Set when a part is opened from a scanned zone's contents, so the count
      # targets that zone rather than the part's largest stock.
      preferred_location_id: current_organization.storage_locations.find_by(id: params[:zone])&.id,
      recent_scans: recent_scans,
      today_count: scanner_movements.where(created_at: Time.current.all_day).count,
      allow_negative_stock: current_organization.allow_negative_stock
    }
  end

  def create_movement
    part = current_organization.parts.find(scan_params[:part_id])
    location = current_organization.storage_locations.find(scan_params[:storage_location_id])
    delta = scan_params[:quantity_delta].to_i

    movement = current_organization.stock_movements.build(
      part: part,
      storage_location: location,
      user: current_user,
      movement_type: delta.negative? ? "out" : "in",
      quantity_delta: delta,
      reason: SCANNER_REASON
    )

    if movement.save
      redirect_back_or_to scan_path, notice: "Movement recorded successfully."
    else
      redirect_back_or_to scan_path, alert: "Failed to record movement.", inertia: { errors: inertia_errors(movement, as: :stock_movement) }
    end
  end

  private

  def scan_params
    params.require(:scan).permit(:part_id, :storage_location_id, :quantity_delta)
  end

  def lookup(code)
    if (part = find_part(code))
      { kind: "part", part: serialize_part(part) }
    elsif (location = find_location(code))
      { kind: "location", location: serialize_location(location) }
    else
      { kind: "unknown" }
    end
  end

  # Label QR codes hold a link to this page (`https://host/scan?code=MS-00042`)
  # so a phone's own camera app opens the right record. The in-app camera and
  # hardware scanners read that link as plain text: keep only its code, from
  # whichever host printed it.
  def normalize_code(raw)
    code = raw.to_s.strip
    return code unless code.match?(%r{\Ahttps?://}i)

    uri = URI.parse(code)
    return code unless uri.path.to_s.chomp("/").end_with?("/scan")

    URI.decode_www_form(uri.query.to_s).to_h["code"].to_s.strip.presence || code
  rescue URI::InvalidURIError, ArgumentError
    code
  end

  # IPNs are matched first: they are unique per organization and what labels
  # print, whereas an MPN can be shared by several parts.
  def find_part(code)
    parts = current_organization.parts
    if (match = code.match(PART_CODE))
      return parts.find_by(id: match[1])
    end

    downcased = code.downcase
    parts.find_by("LOWER(ipn) = ?", downcased) ||
      parts.where("LOWER(barcode) = :code OR LOWER(sku) = :code OR LOWER(mpn) = :code", code: downcased).first
  end

  def find_location(code)
    locations = current_organization.storage_locations
    if (match = code.match(ZONE_CODE))
      return locations.find_by(id: match[1])
    end

    locations.where("LOWER(code) = ?", code.downcase).first
  end

  def serialize_part(part)
    # Resolve every zone's full path from one preloaded org-wide map rather than
    # walking the parent chain with a query per level (see #full_path).
    path_cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    storages = part.part_storages.includes(:storage_location).sort_by { |ps| -ps.quantity }
    locations = storages.map do |ps|
      { id: ps.storage_location_id, name: ps.storage_location.full_path(cache: path_cache), quantity: ps.quantity }
    end
    # A part that has never been stored can still receive stock: offer every
    # zone of the organization as a target for an inbound count.
    if locations.empty?
      locations = current_organization.storage_locations.alphabetical.map do |location|
        { id: location.id, name: location.full_path(cache: path_cache), quantity: 0 }
      end
    end

    {
      id: part.id,
      reference: part.reference,
      name: part.name,
      category: part.category ? { name: part.category.name, color: part.category.color } : nil,
      total_quantity: storages.sum(&:quantity),
      stock_status: part.stock_status,
      locations: locations
    }
  end

  def serialize_location(location)
    stored = location.part_storages.with_stock
    contents = stored.includes(:part).order(quantity: :desc).limit(ZONE_CONTENTS_LIMIT).map do |ps|
      { id: ps.part_id, reference: ps.part.reference, name: ps.part.name, quantity: ps.quantity }
    end

    {
      id: location.id,
      name: location.name,
      full_path: location.full_path,
      location_type: location.location_type,
      parts_count: stored.count,
      total_quantity: location.total_quantity,
      children_count: location.children.count,
      contents: contents
    }
  end

  def scanner_movements
    current_organization.stock_movements.where(reason: SCANNER_REASON)
  end

  def recent_scans
    scanner_movements
      .includes(:storage_location, part: :category)
      .recent
      .limit(RECENT_SCANS_LIMIT)
      .map do |movement|
        part = movement.part
        {
          id: movement.id,
          created_at: movement.created_at.iso8601,
          quantity_delta: movement.quantity_delta,
          reference: part.reference,
          location_name: movement.storage_location.name,
          category_color: part.category&.color
        }
      end
  end
end

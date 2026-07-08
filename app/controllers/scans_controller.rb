# frozen_string_literal: true

class ScansController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create_movement]

  # Movements created from the scanner page carry this reason so the
  # "Recent scans" feed can be rebuilt from the ledger without a scan table.
  SCANNER_REASON = "Scanner count"
  RECENT_SCANS_LIMIT = 6

  def index
    code = params[:code].to_s.strip

    render inertia: "scans/index", props: {
      code: code.presence,
      result: code.present? ? lookup(code) : nil,
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
      redirect_back_or_to scan_path, alert: "Failed to record movement.", inertia: { errors: movement.errors }
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

  def find_part(code)
    current_organization.parts
      .where("LOWER(barcode) = :code OR LOWER(sku) = :code OR LOWER(mpn) = :code", code: code.downcase)
      .first
  end

  def find_location(code)
    current_organization.storage_locations.where("LOWER(code) = ?", code.downcase).first
  end

  def serialize_part(part)
    storages = part.part_storages.includes(:storage_location).sort_by { |ps| -ps.quantity }
    locations = storages.map do |ps|
      { id: ps.storage_location_id, name: ps.storage_location.full_path, quantity: ps.quantity }
    end
    # A part that has never been stored can still receive stock: offer every
    # zone of the organization as a target for an inbound count.
    if locations.empty?
      locations = current_organization.storage_locations.alphabetical.map do |location|
        { id: location.id, name: location.full_path, quantity: 0 }
      end
    end

    {
      id: part.id,
      reference: part.mpn.presence || part.sku.presence || part.name,
      name: part.name,
      category: part.category ? { name: part.category.name, color: part.category.color } : nil,
      total_quantity: part.total_quantity,
      stock_status: part.stock_status,
      locations: locations
    }
  end

  def serialize_location(location)
    {
      id: location.id,
      name: location.name,
      full_path: location.full_path,
      location_type: location.location_type,
      parts_count: location.part_storages.with_stock.count,
      total_quantity: location.total_quantity,
      children_count: location.children.count
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
          reference: part.mpn.presence || part.sku.presence || part.name,
          location_name: movement.storage_location.name,
          category_color: part.category&.color
        }
      end
  end
end

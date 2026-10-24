# frozen_string_literal: true

class ScansController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create_movement receive sync]

  # Movements created from the scanner page carry this reason so the
  # "Recent scans" feed can be rebuilt from the ledger without a scan table.
  SCANNER_REASON = "Scanner count"
  # Bags received by scanning their supplier label (see SupplierLabel).
  LABEL_REASON = "Received from supplier label"
  RECENT_SCANS_LIMIT = 6
  ZONE_CONTENTS_LIMIT = 50

  def index
    code = ScanCode.normalize(params[:code])

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
    delta = Quantity.parse(scan_params[:quantity_delta]) || 0

    movement = current_organization.stock_movements.build(
      part: part,
      storage_location: location,
      user: current_user,
      movement_type: delta.negative? ? "out" : "in",
      quantity_delta: delta,
      reason: SCANNER_REASON
    )

    if movement.save
      redirect_back_or_to scan_path, notice: t("flash.scans.movement_recorded_successfully")
    else
      redirect_back_or_to scan_path, alert: t("flash.scans.failed_to_record_movement"), inertia: { errors: inertia_errors(movement, as: :stock_movement) }
    end
  end

  # Receives a scanned supplier bag: one inbound movement of the label's
  # quantity (editable on the page), stamped with the label's order so a second
  # scan of the same bag can be flagged.
  def receive
    part = current_organization.parts.find(receive_params[:part_id])
    location = current_organization.storage_locations.find(receive_params[:storage_location_id])
    quantity = Quantity.parse(receive_params[:quantity]) || 0

    movement = current_organization.stock_movements.build(
      part: part,
      storage_location: location,
      user: current_user,
      movement_type: "in",
      quantity_delta: quantity,
      reason: LABEL_REASON,
      reference: receive_params[:reference].to_s.strip.first(255).presence
    )

    if movement.save
      redirect_to scan_path, notice: t("flash.scans.bag_received", quantity: Quantity.format(quantity, part.unit), reference: part.reference, zone: location.name)
    else
      redirect_back_or_to scan_path, alert: t("flash.scans.bag_receive_failed"), inertia: { errors: inertia_errors(movement, as: :stock_movement) }
    end
  end

  # What the page keeps on the device to scan without a network (see
  # OfflineScanSnapshot), plus a fresh CSRF token: a page reopened from the
  # service worker's cache carries a stale one.
  def offline
    render json: OfflineScanSnapshot.new(current_organization).as_json.merge(csrf_token: form_authenticity_token)
  end

  # Writes the scans queued offline (see OfflineScanSync). Scans queued in
  # another organization than the current one are left for the device to send
  # once that organization is selected again.
  def sync
    if params[:organization_id].to_i != current_organization.id
      return render json: { error: "organization_mismatch" }, status: :conflict
    end

    operations = params.permit(operations: %i[id kind part_id storage_location_id quantity reference scanned_at])[:operations]
    render json: { results: OfflineScanSync.new(current_organization, current_user).call(operations&.map(&:to_h)) }
  end

  private

  def scan_params
    params.require(:scan).permit(:part_id, :storage_location_id, :quantity_delta)
  end

  def receive_params
    params.require(:receipt).permit(:part_id, :storage_location_id, :quantity, :reference)
  end

  def lookup(code)
    scan = ScanCode.new(current_organization)
    if (label = SupplierLabel.parse(code))
      label_lookup(label)
    elsif (part = scan.part(code))
      { kind: "part", part: serialize_part(part) }
    elsif (location = scan.location(code))
      { kind: "location", location: serialize_location(location) }
    else
      { kind: "unknown" }
    end
  end

  def label_lookup(label)
    part = find_label_part(label)

    {
      kind: "supplier_label",
      label: label.as_json,
      reference: label.movement_reference,
      part: part && serialize_part(part),
      previous_receipt: part && previous_receipt(part, label),
      open_orders: part ? open_orders_for(part) : []
    }
  end

  # A customer part number is what the org typed when ordering, usually its
  # IPN; then the distributor's own part number, as the part's SKU or a
  # supplier link's SKU; the MPN last, as it's the least specific.
  def find_label_part(label)
    parts = current_organization.parts

    if label.customer_part_number.present?
      part = parts.find_by("LOWER(ipn) = ?", label.customer_part_number.downcase)
      return part if part
    end

    if label.supplier_sku.present?
      sku = label.supplier_sku.downcase
      part = parts.find_by("LOWER(sku) = ?", sku) ||
        parts.joins(:part_suppliers).where("LOWER(part_suppliers.supplier_sku) = ?", sku).first
      return part if part
    end

    parts.find_by("LOWER(mpn) = ?", label.mpn.downcase) if label.mpn.present?
  end

  # The last receipt of this same bag (same part, order and quantity), so the
  # page can warn before counting it twice. Labels without an order number
  # can't be told apart and are never flagged.
  def previous_receipt(part, label)
    return if label.order_number.blank?

    movement = current_organization.stock_movements
      .where(part: part, reason: LABEL_REASON, reference: label.movement_reference)
      .then { |scope| label.quantity ? scope.where(quantity_delta: label.quantity) : scope }
      .includes(:storage_location)
      .order(created_at: :desc)
      .first
    return unless movement

    {
      created_at: movement.created_at.iso8601,
      quantity: movement.quantity_delta,
      location_name: movement.storage_location.name
    }
  end

  # Open orders for the part: receiving the bag here doesn't close them, and
  # receiving the order afterwards would count the bag a second time.
  def open_orders_for(part)
    OrderLine.joins(:order)
      .where(orders: { organization_id: current_organization.id, status: Order::OPEN_STATUSES }, part_id: part.id)
      .includes(:order)
      .order(:id)
      .map { |line| { id: line.order.id, reference: line.order.reference, quantity: line.quantity } }
  end

  def serialize_part(part)
    # Resolve every zone's full path from one preloaded org-wide map rather than
    # walking the parent chain with a query per level (see #full_path).
    path_cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    storages = part.part_storages.includes(:storage_location).sort_by { |ps| -ps.quantity }
    locations = storages.map do |ps|
      serialize_part_location(ps.storage_location, path_cache, ps.quantity)
    end
    # A part that has never been stored can still receive stock: offer every
    # zone of the organization as a target for an inbound count.
    if locations.empty?
      locations = current_organization.storage_locations.alphabetical.map do |location|
        serialize_part_location(location, path_cache, 0)
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

  # A zone the scanned part can be counted in, for the scanner's zone picker
  # (searchable by path and code).
  def serialize_part_location(location, path_cache, quantity)
    {
      id: location.id,
      name: location.full_path(cache: path_cache),
      code: location.code,
      location_type: location.location_type,
      quantity: quantity
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
      contents: contents,
      # The count already running over this zone, which "Count this zone" opens
      # instead of starting a second one.
      stocktake: current_organization.stocktakes.in_progress.find { |stocktake| stocktake.covers?(location) }
        &.then { |stocktake| { id: stocktake.id, reference: stocktake.reference } }
    }
  end

  def scanner_movements
    current_organization.stock_movements.where(reason: [ SCANNER_REASON, LABEL_REASON ])
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

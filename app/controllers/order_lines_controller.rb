# frozen_string_literal: true

class OrderLinesController < ApplicationController
  include Auth

  # Raised when a storage split is invalid (doesn't sum to the line quantity, or
  # references a foreign zone); rescued into a flash alert.
  class AllocationError < StandardError; end

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_order
  before_action :ensure_editable

  def create
    part = current_organization.parts.find_by(id: params.dig(:order_line, :part_id))
    unless part
      redirect_to order_path(@order), alert: "Choose a part to add to this order."
      return
    end

    line = @order.order_lines.build(
      part: part,
      quantity: line_params[:quantity].presence || 1,
      unit_price: line_params.key?(:unit_price) ? line_params[:unit_price] : default_price(part)
    )

    if line.save
      @order.recalculate_total!
      redirect_to order_path(@order), notice: "Added #{part.reference} to the order."
    else
      redirect_to order_path(@order), alert: line.errors.full_messages.to_sentence.presence || "Could not add that part."
    end
  end

  def update
    line = @order.order_lines.find(params[:id])
    ActiveRecord::Base.transaction do
      # A quantity change drops the old split (OrderLine#clear_stale_allocations);
      # a split sent alongside it is applied after.
      line.update!(line_params)

      if (allocs = allocation_params)
        apply_allocations(line, allocs)
      end
    end

    @order.recalculate_total!
    redirect_to order_path(@order), notice: "Line updated."
  rescue AllocationError => e
    redirect_to order_path(@order), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to order_path(@order), alert: e.record.errors.full_messages.to_sentence.presence || "Could not update that line."
  end

  def destroy
    line = @order.order_lines.find(params[:id])
    line.destroy
    @order.recalculate_total!
    redirect_to order_path(@order), notice: "Line removed."
  end

  # Adds a component discovered through a supplier-catalog search. The part is
  # created in inventory immediately (or reused when its MPN already exists),
  # linked to this order's supplier, and appended as a line — so a not-yet-owned
  # component becomes a real Part the moment it's ordered.
  def catalog
    category = current_organization.categories.find_by(id: params[:category_id])
    unless category
      redirect_to order_path(@order), alert: "Choose a category for the new component."
      return
    end

    part = find_or_build_catalog_part(category)

    # The new part, its supplier link, and the line go in together: a rejected
    # line (e.g. a bad quantity) mustn't leave a stray part in the inventory.
    ActiveRecord::Base.transaction do
      part.save! unless part.persisted?
      link_order_supplier(part)

      @order.order_lines.create!(part: part, quantity: line_params[:quantity].presence || 1, unit_price: catalog_unit_price(part))
      @order.recalculate_total!
    end

    redirect_to order_path(@order), notice: "Added #{part.reference} to the order."
  rescue ActiveRecord::RecordInvalid => e
    fallback = e.record.is_a?(Part) ? "Could not create the component." : "Could not add that component."
    redirect_to order_path(@order), alert: e.record.errors.full_messages.to_sentence.presence || fallback
  end

  private

  def set_order
    @order = current_organization.orders.find(params[:order_id])
  end

  # Frozen orders (received/cancelled) can't have their lines changed — that
  # would desync the stock already credited on receipt.
  def ensure_editable
    return if @order.editable?

    redirect_to order_path(@order), alert: "This order is #{@order.status} and can no longer be edited."
  end

  def line_params
    params.require(:order_line).permit(:quantity, :unit_price)
  end

  # Normalized allocation rows from the request, or nil when the key is absent
  # (so a price-only edit leaves allocations untouched). Blank-zone rows dropped.
  def allocation_params
    raw = params.dig(:order_line, :allocations)
    return nil if raw.nil?

    Array(raw)
      .map { |a| { storage_location_id: a[:storage_location_id], quantity: a[:quantity].to_i } }
      .reject { |a| a[:storage_location_id].blank? }
  end

  # Replaces +line+'s allocations with +allocs+. An empty set clears them (line
  # reverts to the fallback location); a non-empty set must sum to the line
  # quantity and reference zones in this org. Raises AllocationError otherwise.
  def apply_allocations(line, allocs)
    if allocs.empty?
      line.allocations.destroy_all
      return
    end

    unless allocs.sum { |a| a[:quantity] } == line.quantity
      raise AllocationError, "The storage split must add up to the line quantity (#{line.quantity})."
    end

    ids = allocs.map { |a| a[:storage_location_id].to_s }.uniq
    known = current_organization.storage_locations.where(id: ids).pluck(:id).map(&:to_s)
    raise AllocationError, "A chosen storage zone doesn't belong to this organization." unless (ids - known).empty?

    line.allocations.destroy_all
    allocs.each { |a| line.allocations.create!(storage_location_id: a[:storage_location_id], quantity: a[:quantity]) }
  end

  def catalog_part_params
    params.require(:part).permit(
      :name, :mpn, :sku, :manufacturer, :description,
      :value, :tolerance, :voltage_rating, :power_rating, :package_type,
      :unit_price, :rohs_compliant
    )
  end

  # Reuse an existing inventory part with the same MPN (catalog searches often
  # surface parts already stocked) rather than tripping the per-org MPN
  # uniqueness validation; otherwise build a fresh one from the catalog fields.
  def find_or_build_catalog_part(category)
    attrs = catalog_part_params
    mpn = attrs[:mpn].to_s.strip

    if mpn.present?
      existing = current_organization.parts.where("LOWER(mpn) = ?", mpn.downcase).first
      return existing if existing
    end

    part = current_organization.parts.build(attrs)
    part.category = category
    part.image_source_url = params[:image_url].presence
    part
  end

  # Ensure the part is linked to this order's supplier so the price and SKU are
  # remembered for reordering. Best-effort: a link failure never blocks the line.
  def link_order_supplier(part)
    link = part.part_suppliers.find_or_initialize_by(supplier_id: @order.supplier_id)
    link.supplier_sku = params[:supplier_sku].presence if link.supplier_sku.blank?
    link.url = params[:product_url].presence if link.url.blank?
    link.unit_price ||= catalog_part_params[:unit_price].presence
    link.is_preferred = true unless part.part_suppliers.preferred.where.not(id: link.id).exists?
    link.save
  end

  def catalog_unit_price(part)
    catalog_part_params[:unit_price].presence ||
      part.part_suppliers.find_by(supplier_id: @order.supplier_id)&.unit_price ||
      part.unit_price
  end

  # Best available price for prefilling a new line, keyed to this order's supplier.
  def default_price(part)
    part.order_unit_price(@order.supplier_id)
  end
end

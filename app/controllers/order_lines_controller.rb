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
      redirect_to order_path(@order), alert: t("flash.order_lines.choose_a_part_to_add_to")
      return
    end

    previous_quantity = line_quantity_before(part)
    line = line_for(part, line_params[:quantity].presence || 1)
    # The add dialog sends a blank price for "Auto".
    if line_params[:unit_price].present?
      line.unit_price = line_params[:unit_price]
    else
      line.follow_price_breaks(previous_quantity)
    end

    if line.save
      @order.recalculate_total!
      redirect_to order_path(@order), notice: t("flash.order_lines.added_to_the_order", reference: part.reference)
    else
      redirect_to order_path(@order), alert: line.errors.full_messages.to_sentence.presence || t("flash.order_lines.could_not_add_that_part")
    end
  end

  def update
    line = @order.order_lines.find(params[:id])
    ActiveRecord::Base.transaction do
      # A quantity change drops the old split (OrderLine#clear_stale_allocations);
      # a split sent alongside it is applied after.
      previous_quantity = line.quantity
      line.assign_attributes(line_params)
      line.follow_price_breaks(previous_quantity) if line.quantity_changed? && !line_params.key?(:unit_price)
      line.save!

      if (allocs = allocation_params)
        apply_allocations(line, allocs)
      end
    end

    @order.recalculate_total!
    redirect_to order_path(@order), notice: t("flash.order_lines.line_updated")
  rescue AllocationError => e
    redirect_to order_path(@order), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to order_path(@order), alert: e.record.errors.full_messages.to_sentence.presence || t("flash.order_lines.could_not_update_that_line")
  end

  def destroy
    line = @order.order_lines.find(params[:id])
    line.destroy
    @order.recalculate_total!
    redirect_to order_path(@order), notice: t("flash.order_lines.line_removed")
  end

  # Adds a component discovered through a supplier-catalog search. The part is
  # created in inventory immediately (or reused when its MPN already exists),
  # linked to this order's supplier, and appended as a line — so a not-yet-owned
  # component becomes a real Part the moment it's ordered.
  def catalog
    category = current_organization.categories.find_by(id: params[:category_id])
    unless category
      redirect_to order_path(@order), alert: t("flash.order_lines.choose_a_category_for_the_new")
      return
    end

    part = find_or_build_catalog_part(category)

    # The new part, its supplier link, and the line go in together: a rejected
    # line (e.g. a bad quantity) mustn't leave a stray part in the inventory.
    ActiveRecord::Base.transaction do
      part.save! unless part.persisted?
      link_order_supplier(part)

      previous_quantity = line_quantity_before(part)
      line = line_for(part, line_params[:quantity].presence || 1)
      line.follow_price_breaks(previous_quantity)
      line.save!
      @order.recalculate_total!
    end

    redirect_to order_path(@order), notice: t("flash.order_lines.added_to_the_order", reference: part.reference)
  rescue ActiveRecord::RecordInvalid => e
    fallback = e.record.is_a?(Part) ? t("flash.order_lines.could_not_create_the_component") : t("flash.order_lines.could_not_add_that_component")
    redirect_to order_path(@order), alert: e.record.errors.full_messages.to_sentence.presence || fallback
  end

  private

  # The order's line for +part+ with +quantity+ more on it: an existing line is
  # topped up rather than duplicated, so receipt, totals and project imports
  # (which already merge by part) all see one line per part.
  def line_for(part, quantity)
    line = @order.order_lines.find_or_initialize_by(part: part)
    added = quantity.to_s.match?(/\A\d+\z/) ? quantity.to_i : 0
    # Anything but a positive whole number leaves 0, which the line's
    # validation rejects, rather than silently adding nothing.
    line.quantity = added.positive? ? line.quantity.to_i + added : 0
    line
  end

  # The quantity already on the order for +part+ (nil when it isn't on it).
  def line_quantity_before(part)
    @order.order_lines.find_by(part: part)&.quantity
  end

  def set_order
    @order = current_organization.orders.find(params[:order_id])
  end

  # Frozen orders (received/cancelled) can't have their lines changed — that
  # would desync the stock already credited on receipt.
  def ensure_editable
    return if @order.editable?

    redirect_to order_path(@order), alert: t("flash.order_lines.this_order_is_and_can_no", status: t("order_statuses.#{@order.status}"))
  end

  def line_params
    params.require(:order_line).permit(:quantity, :unit_price)
  end

  # Normalized allocation rows from the request, or nil when the key is absent
  # (so a price-only edit leaves allocations untouched). Blank-zone rows dropped.
  # Accepts a list or an index-keyed hash ({ "0" => {...} }, as plain form
  # encoding sends it), which Array() would wrap as one row and so wipe the split.
  def allocation_params
    raw = params.dig(:order_line, :allocations)
    return nil if raw.nil?

    rows = raw.respond_to?(:values) ? raw.values : Array(raw)
    rows
      .select { |a| a.respond_to?(:key?) }
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
      raise AllocationError, t("flash.order_lines.the_storage_split_must_add_up", quantity: line.quantity)
    end

    ids = allocs.map { |a| a[:storage_location_id].to_s }.uniq
    known = current_organization.storage_locations.where(id: ids).pluck(:id).map(&:to_s)
    raise AllocationError, t("flash.order_lines.a_chosen_storage_zone_doesn_t") unless (ids - known).empty?

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
    part.image_source_url = Part.supplier_image_url(params[:image_url])
    part
  end

  # Ensure the part is linked to this order's supplier so the price and SKU are
  # remembered for reordering. Best-effort: a link failure never blocks the line.
  def link_order_supplier(part)
    link = part.part_suppliers.find_or_initialize_by(supplier_id: @order.supplier_id)
    link.supplier_sku = params[:supplier_sku].presence if link.supplier_sku.blank?
    link.url = params[:product_url].presence if link.url.blank?
    link.unit_price ||= catalog_part_params[:unit_price].presence
    link.price_breaks = catalog_price_breaks if link.price_breaks.blank?
    link.is_preferred = true unless part.part_suppliers.preferred.where.not(id: link.id).exists?
    link.save
  end

  # The catalog result's price breaks, as the lookup returned them.
  def catalog_price_breaks
    Array(params[:price_breaks]).filter_map { |row| row.permit(:quantity, :unit_price).to_h if row.respond_to?(:permit) }
  end
end

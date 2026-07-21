# frozen_string_literal: true

class OrderLinesController < ApplicationController
  include Auth

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

    if line.update(line_params)
      @order.recalculate_total!
      redirect_to order_path(@order), notice: "Line updated."
    else
      redirect_to order_path(@order), alert: line.errors.full_messages.to_sentence.presence || "Could not update that line."
    end
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
    unless part.persisted? || part.save
      redirect_to order_path(@order), alert: part.errors.full_messages.to_sentence.presence || "Could not create the component."
      return
    end

    link_order_supplier(part)

    line = @order.order_lines.build(part: part, quantity: line_params[:quantity].presence || 1, unit_price: catalog_unit_price(part))
    if line.save
      @order.recalculate_total!
      redirect_to order_path(@order), notice: "Added #{part.reference} to the order."
    else
      redirect_to order_path(@order), alert: line.errors.full_messages.to_sentence.presence || "Could not add that component."
    end
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

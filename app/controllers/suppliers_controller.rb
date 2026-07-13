# frozen_string_literal: true

class SuppliersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_supplier, only: %i[update destroy]

  def index
    suppliers = current_organization.suppliers
      .includes(part_suppliers: :part, purchases: :purchase_lines)
      .alphabetical

    render inertia: "suppliers/index", props: {
      suppliers: suppliers.map { |supplier| serialize_supplier(supplier) }
    }
  end

  def create
    supplier = current_organization.suppliers.build(supplier_params)

    if supplier.save
      redirect_to suppliers_path, notice: "Supplier created successfully."
    else
      redirect_back_or_to suppliers_path, alert: "Failed to create supplier.", inertia: { errors: inertia_errors(supplier, as: :supplier) }
    end
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to suppliers_path, notice: "Supplier updated successfully."
    else
      redirect_back_or_to suppliers_path, alert: "Failed to update supplier.", inertia: { errors: inertia_errors(@supplier, as: :supplier) }
    end
  end

  def destroy
    if @supplier.destroy
      redirect_to suppliers_path, notice: "Supplier deleted successfully."
    else
      redirect_to suppliers_path, alert: @supplier.errors.full_messages.to_sentence
    end
  end

  private

  def set_supplier
    @supplier = current_organization.suppliers.find(params[:id])
  end

  def supplier_params
    params.require(:supplier).permit(:name, :email, :phone, :website, :country, :city)
  end

  def serialize_supplier(supplier)
    part_suppliers = supplier.part_suppliers
    lead_times = part_suppliers.filter_map(&:lead_time_days)
    last_purchase = supplier.purchases.max_by(&:ordered_at)
    stock_value = part_suppliers.sum { |ps| (ps.part.unit_price || 0) * ps.part.total_quantity }

    {
      id: supplier.id,
      name: supplier.name,
      email: supplier.email,
      phone: supplier.phone,
      website: supplier.website,
      country: supplier.country,
      city: supplier.city,
      reference_count: part_suppliers.size,
      avg_lead_time_days: lead_times.any? ? (lead_times.sum.to_f / lead_times.size).round : nil,
      stock_value: stock_value.to_f,
      last_order_at: last_purchase&.ordered_at&.iso8601,
      order_count: supplier.purchases.size,
      components: part_suppliers.map { |ps| serialize_linked_component(ps) },
      orders: supplier.purchases.sort_by { |p| p.ordered_at || p.created_at }.reverse.map { |purchase| serialize_purchase(purchase) }
    }
  end

  def serialize_linked_component(part_supplier)
    part = part_supplier.part
    {
      id: part.id,
      reference: part.mpn.presence || part.sku.presence || part.name,
      name: part.name,
      quantity: part.total_quantity,
      low_stock: part.low_stock?,
      unit_price: part_supplier.unit_price&.to_f
    }
  end

  def serialize_purchase(purchase)
    {
      id: purchase.id,
      reference: purchase.reference,
      ordered_at: purchase.ordered_at&.iso8601,
      status: purchase.status,
      total_amount: (purchase.total_amount || purchase.computed_total).to_f
    }
  end
end

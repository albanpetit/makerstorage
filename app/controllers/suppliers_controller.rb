# frozen_string_literal: true

class SuppliersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_supplier, only: %i[update destroy]
  before_action :verify_catalog_supplier_authority, only: :destroy

  def index
    suppliers = current_organization.suppliers
      .includes(part_suppliers: { part: :part_storages }, orders: :order_lines)
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
    provider = @supplier.catalog_provider

    if @supplier.destroy
      clear_catalog_credentials(provider) if provider
      redirect_to suppliers_path, notice: destroy_notice(provider)
    else
      redirect_to suppliers_path, alert: @supplier.errors.full_messages.to_sentence
    end
  end

  private

  # Deleting a catalog supplier also removes the integration it fronts, so wipe
  # the matching stored credentials — otherwise Settings would still claim the
  # provider is configured with no supplier to fill prices into.
  def clear_catalog_credentials(provider)
    case provider
    when "mouser"
      current_organization.update!(mouser_api_key: nil)
    when "digikey"
      current_organization.update!(
        digikey_client_id: nil, digikey_client_secret: nil,
        digikey_access_token: nil, digikey_refresh_token: nil, digikey_token_expires_at: nil
      )
    end
  end

  def destroy_notice(provider)
    return "Supplier deleted successfully." unless provider

    label = Supplier::CATALOG_PROVIDER_DEFAULTS.dig(provider, :name) || provider
    "Supplier deleted. The #{label} catalog integration has been disabled."
  end

  def set_supplier
    @supplier = current_organization.suppliers.find(params[:id])
  end

  # Deleting a catalog supplier (Mouser, DigiKey) also disconnects its
  # integration and clears the organization's credentials, which only admins
  # may manage (see SettingsController).
  def verify_catalog_supplier_authority
    return unless @supplier.catalog_provider
    return if current_user.admin_of?(current_organization)

    redirect_to suppliers_path, alert: "Only an admin can delete a catalog supplier, since it disconnects the integration."
  end

  def supplier_params
    params.require(:supplier).permit(:name, :email, :phone, :website, :country, :city)
  end

  def serialize_supplier(supplier)
    part_suppliers = supplier.part_suppliers
    lead_times = part_suppliers.filter_map(&:lead_time_days)
    last_order = supplier.orders.max_by(&:ordered_at)
    stock_value = part_suppliers.sum { |ps| (ps.part.unit_price || 0) * ps.part.total_quantity }

    {
      id: supplier.id,
      name: supplier.name,
      email: supplier.email,
      phone: supplier.phone,
      website: supplier.website,
      country: supplier.country,
      city: supplier.city,
      catalog_provider: supplier.catalog_provider,
      reference_count: part_suppliers.size,
      avg_lead_time_days: lead_times.any? ? (lead_times.sum.to_f / lead_times.size).round : nil,
      stock_value: stock_value.to_f,
      last_order_at: last_order&.ordered_at&.iso8601,
      order_count: supplier.orders.size,
      components: part_suppliers.map { |ps| serialize_linked_component(ps) },
      orders: supplier.orders.sort_by { |o| o.ordered_at || o.created_at }.reverse.map { |order| serialize_order(order) }
    }
  end

  def serialize_linked_component(part_supplier)
    part = part_supplier.part
    {
      id: part.id,
      reference: part.reference,
      name: part.name,
      quantity: part.total_quantity,
      low_stock: part.low_stock?,
      unit_price: part_supplier.unit_price&.to_f
    }
  end

  def serialize_order(order)
    {
      id: order.id,
      reference: order.reference,
      ordered_at: order.ordered_at&.iso8601,
      status: order.status,
      total_amount: (order.total_amount || order.computed_total).to_f
    }
  end
end

# frozen_string_literal: true

class SuppliersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_supplier, only: %i[update destroy]
  before_action :verify_catalog_supplier_authority, only: :destroy

  # The list carries each supplier's figures, computed in SQL; the components
  # and orders of one supplier are loaded when its sheet opens
  # (`supplier_detail`, a partial reload with ?supplier=ID).
  def index
    suppliers = current_organization.suppliers.alphabetical.to_a
    summaries = supplier_summaries(suppliers.map(&:id))

    render inertia: "suppliers/index", props: {
      suppliers: suppliers.map { |supplier| serialize_supplier(supplier, summaries) },
      supplier_detail: InertiaRails.optional { serialize_supplier_detail(current_organization.suppliers.find_by(id: params[:supplier])) }
    }
  end

  def create
    supplier = current_organization.suppliers.build(supplier_params)

    if supplier.save
      redirect_to suppliers_path, notice: t("flash.suppliers.supplier_created_successfully")
    else
      redirect_back_or_to suppliers_path, alert: t("flash.suppliers.failed_to_create_supplier"), inertia: { errors: inertia_errors(supplier, as: :supplier) }
    end
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to suppliers_path, notice: t("flash.suppliers.supplier_updated_successfully")
    else
      redirect_back_or_to suppliers_path, alert: t("flash.suppliers.failed_to_update_supplier"), inertia: { errors: inertia_errors(@supplier, as: :supplier) }
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
      current_organization.update!(mouser_api_key: nil, mouser_order_api_key: nil)
    when "digikey"
      current_organization.update!(
        digikey_client_id: nil, digikey_client_secret: nil,
        digikey_access_token: nil, digikey_refresh_token: nil, digikey_token_expires_at: nil
      )
    when "lcsc"
      current_organization.update!(lcsc_enabled: false)
    end
  end

  def destroy_notice(provider)
    return t("flash.suppliers.supplier_deleted_successfully") unless provider

    label = Supplier::CATALOG_PROVIDER_DEFAULTS.dig(provider, :name) || provider
    t("flash.suppliers.supplier_deleted_the_catalog_integration_has", label: label)
  end

  def set_supplier
    @supplier = current_organization.suppliers.find(params[:id])
  end

  # Deleting a catalog supplier (Mouser, DigiKey, LCSC) also disconnects its
  # integration and clears the organization's credentials, which only admins
  # may manage (see SettingsController).
  def verify_catalog_supplier_authority
    return unless @supplier.catalog_provider
    return if current_user.admin_of?(current_organization)

    redirect_to suppliers_path, alert: t("flash.suppliers.only_an_admin_can_delete_a")
  end

  def supplier_params
    params.require(:supplier).permit(:name, :email, :phone, :website, :country, :city)
  end

  # supplier id => { references:, lead_time:, stock_value:, orders:, last_order_at: }
  def supplier_summaries(ids)
    links = PartSupplier.where(supplier_id: ids)
    references = links.group(:supplier_id).count
    lead_times = links.where.not(lead_time_days: nil).group(:supplier_id).average(:lead_time_days)
    stock = PartStorage.group(:part_id).select("part_id, SUM(quantity) AS quantity")
    stock_values = links.joins(:part).joins("LEFT JOIN (#{stock.to_sql}) stock ON stock.part_id = part_suppliers.part_id")
      .group(:supplier_id).sum(Arel.sql("COALESCE(parts.unit_price, 0) * COALESCE(stock.quantity, 0)"))
    orders = current_organization.orders.where(supplier_id: ids).group(:supplier_id)
    order_counts = orders.count
    last_orders = orders.maximum(:ordered_at)

    ids.index_with do |id|
      { references: references.fetch(id, 0), lead_time: lead_times[id], stock_value: stock_values.fetch(id, 0),
        orders: order_counts.fetch(id, 0), last_order_at: last_orders[id] }
    end
  end

  def serialize_supplier(supplier, summaries)
    summary = summaries.fetch(supplier.id)

    {
      id: supplier.id,
      name: supplier.name,
      email: supplier.email,
      phone: supplier.phone,
      website: supplier.website,
      country: supplier.country,
      city: supplier.city,
      catalog_provider: supplier.catalog_provider,
      reference_count: summary[:references],
      avg_lead_time_days: summary[:lead_time]&.to_f&.round,
      stock_value: summary[:stock_value].to_f,
      last_order_at: summary[:last_order_at]&.iso8601,
      order_count: summary[:orders]
    }
  end

  def serialize_supplier_detail(supplier)
    return nil unless supplier

    {
      id: supplier.id,
      components: supplier.part_suppliers.includes(part: :part_storages).map { |ps| serialize_linked_component(ps) },
      orders: supplier.orders.includes(:order_lines).sort_by { |o| o.ordered_at || o.created_at }.reverse.map { |order| serialize_order(order) }
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

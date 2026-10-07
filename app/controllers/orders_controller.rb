# frozen_string_literal: true

class OrdersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy advance import_project push_to_cart import_supplier_order assign_storage]
  before_action :set_order, only: %i[show update destroy advance import_project push_to_cart assign_storage]

  def index
    orders = current_organization.orders
      .includes(:supplier, :order_lines)
      .order(created_at: :desc)

    render inertia: "orders/index", props: {
      orders: orders.map { |order| serialize_order_summary(order) },
      suppliers: supplier_options,
      mouser_order_enabled: current_organization.mouser_order_configured?,
      digikey_order_enabled: current_organization.digikey_account_connected?
    }
  end

  def show
    render inertia: "orders/show", props: {
      order: serialize_order(@order),
      suppliers: supplier_options,
      # Lightweight pick-list for the "add from inventory" combobox.
      parts: current_organization.parts.alphabetical.map do |part|
        { id: part.id, reference: part.reference, name: part.name, mpn: part.mpn, sku: part.sku }
      end,
      # Catalog search tab: category pick-list + whether any provider is configured.
      categories: current_organization.categories.order(:name).map { |c| { id: c.id, name: c.name } },
      catalog_enabled: current_organization.supplier_lookup_configured?,
      # Project BOM import: pick-list of projects with a line count.
      projects: current_organization.projects.recent.includes(:project_lines).map do |project|
        { id: project.id, name: project.name, reference: project.reference, line_count: project.project_lines.size }
      end,
      # Mouser cart push is only meaningful when the key is set and this order is
      # for the Mouser supplier (its lines carry Mouser part numbers).
      mouser_cart_enabled: current_organization.mouser_order_configured? && @order.supplier.catalog_provider == "mouser",
      # Storage zones (flat, with parent_id) for the tree picker used to target
      # where received components land.
      storage_locations: current_organization.storage_locations.alphabetical.map { |l| serialize_storage_location(l) }
    }
  end

  def create
    supplier = current_organization.suppliers.find_by(id: order_params[:supplier_id])
    unless supplier
      redirect_to orders_path, alert: "Choose a supplier to create an order."
      return
    end

    order = current_organization.orders.new(order_params)
    # A new order always starts the lifecycle: creating one as received would
    # skip the stock receipt, and cancelled makes no sense for a fresh order.
    order.status = "pending"
    order.ordered_at ||= Date.current
    order.reference = Order.next_reference(current_organization, supplier) if order.reference.blank?

    if order.save
      redirect_to order_path(order), notice: "Order #{order.reference} created."
    else
      redirect_to orders_path, alert: order.errors.full_messages.to_sentence.presence || "Could not create order.",
        inertia: { errors: inertia_errors(order, as: :order) }
    end
  end

  def update
    # Receiving credits stock, so it must go through #advance — never a plain
    # attribute write that would skip the ledger update.
    if order_params[:status] == "received"
      redirect_to order_path(@order), alert: "Use “Mark received” to receive an order so stock is credited."
      return
    end

    if @order.update(order_params)
      redirect_to order_path(@order), notice: "Order updated."
    else
      redirect_to order_path(@order), alert: @order.errors.full_messages.to_sentence.presence || "Could not update order.",
        inertia: { errors: inertia_errors(@order, as: :order) }
    end
  end

  def destroy
    @order.destroy!
    redirect_to orders_path, notice: "Order deleted."
  end

  def advance
    # Preload each line's part and its storage locations so stock receipt reads
    # `line.part.storage_locations.first` off memory instead of an N+1.
    @order = current_organization.orders
      .includes(order_lines: [ { part: :storage_locations }, { allocations: :storage_location } ])
      .find(params[:id])

    result = @order.advance!(user: current_user)

    unless result.advanced
      redirect_to order_path(@order), alert: "This order is already received or cancelled."
      return
    end

    if result.skipped.any?
      redirect_to order_path(@order),
        notice: "Order #{@order.reference} marked as received.",
        alert: "No stock was recorded for #{result.skipped.to_sentence} — #{result.skipped.one? ? 'it has' : 'they have'} no storage location. Add a location and record the movement manually."
      return
    end

    redirect_to order_path(@order), notice: "Order #{@order.reference} marked as #{result.status}."
  end

  # Pulls a project's BOM into this order. Each matched line becomes (or tops up)
  # an order line; "shortfall" mode orders only what stock can't cover, "full"
  # orders the whole required quantity. Unmatched BOM lines can't be ordered, so
  # they're surfaced as a warning rather than silently dropped.
  def import_project
    unless @order.editable?
      redirect_to order_path(@order), alert: "This order is #{@order.status} and can no longer be edited."
      return
    end

    project = current_organization.projects
      .includes(project_lines: { part: [ :part_storages, { part_suppliers: :supplier } ] })
      .find(params[:project_id])

    # Per part, summed across BOM lines (a part can appear on several).
    quantities = params[:mode].to_s == "shortfall" ? project.shortfall_by_part : project.required_by_part
    added = 0

    quantities.each do |part, quantity|
      next unless quantity.positive?

      line = @order.order_lines.find_or_initialize_by(part_id: part.id)
      line.quantity = line.quantity.to_i + quantity
      line.unit_price ||= part.order_unit_price(@order.supplier_id)
      line.save!
      added += 1
    end

    @order.recalculate_total!

    if added.zero?
      redirect_to order_path(@order), alert: "Nothing to import from #{project.name} — no matched line needed ordering."
      return
    end

    skipped = project.unmatched_lines.size
    notice = "Imported #{added} line#{'s' if added != 1} from #{project.name}."
    if skipped.positive?
      redirect_to order_path(@order), notice: notice,
        alert: "#{skipped} BOM line#{'s' if skipped != 1} had no matching part and #{skipped == 1 ? 'was' : 'were'} skipped."
    else
      redirect_to order_path(@order), notice: notice
    end
  end

  # Bulk-presets a single target storage zone for every line: each line gets one
  # full-quantity allocation at +storage_location_id+, replacing any existing
  # split. Operators then override special cases per line.
  def assign_storage
    unless @order.editable?
      redirect_to order_path(@order), alert: "This order is #{@order.status} and can no longer be edited."
      return
    end

    location = current_organization.storage_locations.find_by(id: params[:storage_location_id])
    unless location
      redirect_to order_path(@order), alert: "Choose a storage zone to assign."
      return
    end

    ActiveRecord::Base.transaction do
      @order.order_lines.each do |line|
        line.allocations.destroy_all
        line.allocations.create!(storage_location: location, quantity: line.quantity)
      end
    end

    count = @order.order_lines.size
    redirect_to order_path(@order), notice: "Storage zone set for #{count} line#{'s' if count != 1}."
  end

  # Pushes this order's lines to a Mouser cart via the Order/Cart API, returning
  # live pricing and (when Mouser provides one) a checkout URL. Only lines with a
  # known Mouser part number can be added, so the rest are reported as skipped.
  def push_to_cart
    client = SupplierCatalog.mouser_order_client(current_organization)
    unless client
      redirect_to order_path(@order), alert: "Add a Mouser Order API key in Settings → Integrations to build a cart."
      return
    end

    skus = @order.order_lines.map { |line| [ line, mouser_sku_for(line) ] }
    items = skus.filter_map { |line, sku| { supplier_sku: sku, quantity: line.quantity } if sku.present? }

    if items.empty?
      redirect_to order_path(@order), alert: "No line has a Mouser part number. Add components via a Mouser catalog search first."
      return
    end

    cart = client.create_cart(items, currency: current_organization.currency)

    notice = "Built a Mouser cart with #{items.size} line#{'s' if items.size != 1}"
    notice += " totalling #{cart.merchandise_total} #{cart.currency}" if cart.merchandise_total.present?
    notice += "."
    notice += " Checkout: #{cart.checkout_url}" if cart.checkout_url.present?
    skipped = skus.count { |_line, sku| sku.blank? }
    notice += " #{skipped} line#{'s' if skipped != 1} without a Mouser part number were skipped." if skipped.positive?

    redirect_to order_path(@order), notice: notice
  rescue SupplierCatalog::LookupError => e
    redirect_to order_path(@order), alert: e.message
  end

  # Imports a placed supplier order (Mouser web order number, or DigiKey sales
  # order number) into a new local order, reconciling each line to an existing
  # part or creating one.
  def import_supplier_order
    provider = params[:provider].presence || "mouser"
    client = order_client_for(provider)
    unless client
      redirect_to orders_path, alert: order_client_missing_message(provider)
      return
    end

    number = params[:order_number].to_s.strip
    if number.blank?
      redirect_to orders_path, alert: "Enter an order number to import."
      return
    end

    label = provider_label(provider)
    supplier, = Supplier.ensure_catalog_provider(current_organization, provider)
    result = client.import_order(number)

    if result.lines.empty?
      redirect_to orders_path, alert: "#{label} order #{number} has no importable lines."
      return
    end

    reference = result.order_number.presence || number
    if current_organization.orders.exists?(reference: reference)
      redirect_to orders_path, alert: "#{label} order #{reference} has already been imported."
      return
    end

    order = build_imported_order(supplier, result, reference, label)
    redirect_to order_path(order), notice: "Imported #{label} order #{reference} with #{result.lines.size} line#{'s' if result.lines.size != 1}."
  rescue SupplierCatalog::LookupError => e
    redirect_to orders_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to orders_path, alert: "Could not import that order: #{e.record.errors.full_messages.to_sentence}."
  end

  private

  def order_client_for(provider)
    case provider
    when "mouser" then SupplierCatalog.mouser_order_client(current_organization)
    when "digikey" then SupplierCatalog.digikey_order_client(current_organization)
    end
  end

  def order_client_missing_message(provider)
    if provider == "digikey"
      "Connect your DigiKey account in Settings → Integrations to import orders."
    else
      "Add a Mouser Order API key in Settings → Integrations to import orders."
    end
  end

  def provider_label(provider)
    provider == "digikey" ? "DigiKey" : "Mouser"
  end

  # Persists an imported supplier order and its reconciled lines in one transaction.
  def build_imported_order(supplier, result, reference, label)
    ActiveRecord::Base.transaction do
      order = current_organization.orders.create!(
        supplier: supplier,
        status: "pending",
        ordered_at: (Date.parse(result.placed_at.to_s) rescue nil) || Date.current,
        reference: reference,
        notes: [ "Imported from #{label} order #{reference}", result.status ].compact.join(" — ")
      )

      result.lines.each do |line|
        part = reconcile_imported_part(supplier, line)
        order.order_lines.create!(part: part, quantity: line.quantity.positive? ? line.quantity : 1, unit_price: line.unit_price)
      end

      order.recalculate_total!
      order
    end
  end

  # Matches an imported line to an existing part by MPN or Mouser SKU, creating a
  # minimal part (under an "Uncategorized" category) when none exists, and keeps
  # the Mouser supplier link's SKU/price in sync.
  def reconcile_imported_part(supplier, line)
    part = existing_part_for(line)
    part ||= current_organization.parts.create!(
      category: import_category,
      name: (line.description.presence || line.mpn.presence || line.supplier_sku).to_s.slice(0, 255),
      mpn: line.mpn.presence,
      manufacturer: line.manufacturer.presence
    )

    link = part.part_suppliers.find_or_initialize_by(supplier_id: supplier.id)
    link.supplier_sku = line.supplier_sku.presence if link.supplier_sku.blank?
    link.unit_price ||= line.unit_price.presence
    link.save
    part
  end

  def existing_part_for(line)
    if line.mpn.present?
      by_mpn = current_organization.parts.where("LOWER(mpn) = ?", line.mpn.downcase).first
      return by_mpn if by_mpn
    end
    return nil if line.supplier_sku.blank?

    current_organization.parts.joins(:part_suppliers)
      .find_by(part_suppliers: { supplier_sku: line.supplier_sku })
  end

  def import_category
    @import_category ||= current_organization.categories.find_or_create_by!(name: "Uncategorized")
  end

  # The Mouser part number a line carries via its link to this order's supplier.
  def mouser_sku_for(line)
    line.part.part_suppliers.find_by(supplier_id: @order.supplier_id)&.supplier_sku
  end

  def set_order
    @order = current_organization.orders
      .includes(:supplier, order_lines: [ :part, { allocations: :storage_location } ])
      .find(params[:id])
  end

  # id => zone map so each allocation's full path ("Room > Cabinet > Drawer")
  # resolves in memory instead of an N+1 while serializing lines.
  def location_path_cache
    @location_path_cache ||= StorageLocation.full_path_cache(current_organization.storage_locations)
  end

  def order_params
    params.require(:order).permit(:supplier_id, :reference, :status, :ordered_at, :expected_delivery, :notes)
  end

  def supplier_options
    current_organization.suppliers.alphabetical.map { |s| { id: s.id, name: s.name } }
  end

  def serialize_order_summary(order)
    {
      id: order.id,
      reference: order.reference,
      supplier_name: order.supplier.name,
      status: order.status,
      ordered_at: order.ordered_at&.iso8601,
      expected_delivery: order.expected_delivery&.iso8601,
      total_amount: (order.total_amount || order.computed_total).to_f,
      line_count: order.order_lines.size,
      created_at: order.created_at.iso8601
    }
  end

  def serialize_order(order)
    {
      id: order.id,
      reference: order.reference,
      status: order.status,
      editable: order.editable?,
      supplier: { id: order.supplier_id, name: order.supplier.name },
      ordered_at: order.ordered_at&.iso8601,
      expected_delivery: order.expected_delivery&.iso8601,
      notes: order.notes,
      total_amount: (order.total_amount || order.computed_total).to_f,
      lines: order.order_lines.map { |line| serialize_line(line) }
    }
  end

  def serialize_line(line)
    {
      id: line.id,
      quantity: line.quantity,
      unit_price: line.unit_price&.to_f,
      subtotal: line.subtotal&.to_f,
      allocated_quantity: line.allocated_quantity,
      allocations: line.allocations.map { |a| serialize_allocation(a) },
      part: {
        id: line.part.id,
        reference: line.part.reference,
        name: line.part.name
      }
    }
  end

  def serialize_allocation(allocation)
    {
      id: allocation.id,
      storage_location_id: allocation.storage_location_id,
      storage_location_path: allocation.storage_location.full_path(cache: location_path_cache),
      quantity: allocation.quantity
    }
  end

  def serialize_storage_location(location)
    {
      id: location.id,
      name: location.name,
      location_type: location.location_type,
      code: location.code,
      parent_id: location.parent_id
    }
  end
end

# frozen_string_literal: true

# What the Scanner page keeps on the device to keep working without a network
# (app/frontend/lib/offline-scanner): every part with the codes the scanner
# matches and its stock per zone, every zone, open order lines and recent bag
# receipts, so a lookup, a count or a bag receipt can be shown offline the way
# ScansController#lookup would answer it. Plucked rows, no models.
class OfflineScanSnapshot
  # Bag receipts older than this aren't kept for the "already received"
  # warning offline.
  RECEIPTS_SINCE = 1.year
  RECEIPTS_LIMIT = 2000

  def initialize(organization)
    @organization = organization
  end

  def as_json(*)
    {
      organization_id: @organization.id,
      generated_at: Time.current.iso8601,
      allow_negative_stock: @organization.allow_negative_stock,
      parts: parts,
      locations: locations,
      open_orders: open_orders,
      label_receipts: label_receipts
    }
  end

  private

  def parts
    stocks = PartStorage.joins(:part).where(parts: { organization_id: @organization.id }).where.not(quantity: 0)
      .pluck(:part_id, :storage_location_id, :quantity)
      .group_by(&:first)
    supplier_skus = PartSupplier.joins(:part).where(parts: { organization_id: @organization.id })
      .where.not(supplier_sku: [ nil, "" ]).pluck(:part_id, :supplier_sku)
      .group_by(&:first)
    categories = @organization.categories.pluck(:id, :name, :color).to_h { |id, name, color| [ id, { name: name, color: color } ] }

    @organization.parts.order(:id)
      .pluck(:id, :name, :ipn, :barcode, :sku, :mpn, :category_id, :min_stock_threshold)
      .map do |id, name, ipn, barcode, sku, mpn, category_id, threshold|
        {
          id: id,
          reference: mpn.presence || sku.presence || name,
          name: name,
          ipn: ipn,
          barcode: barcode,
          sku: sku,
          mpn: mpn,
          supplier_skus: supplier_skus.fetch(id, []).map(&:last),
          category: categories[category_id],
          min_stock_threshold: Quantity.normalize(threshold || 0),
          # [zone id, quantity] pairs.
          stock: stocks.fetch(id, []).map { |_, location_id, quantity| [ location_id, quantity ] }
        }
      end
  end

  def locations
    scope = @organization.storage_locations
    cache = StorageLocation.full_path_cache(scope)
    scope.order(:name).pluck(:id, :name, :code, :location_type, :parent_id).map do |id, name, code, type, parent_id|
      {
        id: id,
        name: name,
        full_path: cache.fetch(id).full_path(cache: cache),
        code: code,
        location_type: type,
        parent_id: parent_id
      }
    end
  end

  def open_orders
    OrderLine.joins(:order)
      .where(orders: { organization_id: @organization.id, status: Order::OPEN_STATUSES })
      .order(:id)
      .pluck(:part_id, "orders.id", "orders.reference", :quantity)
      .map { |part_id, id, reference, quantity| { part_id: part_id, id: id, reference: reference, quantity: quantity } }
  end

  def label_receipts
    @organization.stock_movements
      .where(reason: ScansController::LABEL_REASON, created_at: RECEIPTS_SINCE.ago..)
      .where.not(reference: nil)
      .joins(:storage_location)
      .order(created_at: :desc)
      .limit(RECEIPTS_LIMIT)
      .pluck(:part_id, :reference, :quantity_delta, :created_at, "storage_locations.name")
      .map do |part_id, reference, quantity, created_at, location_name|
        { part_id: part_id, reference: reference, quantity: quantity, created_at: created_at.iso8601, location_name: location_name }
      end
  end
end

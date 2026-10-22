# frozen_string_literal: true

# Values an organization's stock (Stock value page and its CSV). Each part in
# stock is valued at a unit price picked by +method+:
#   "current"  the part's unit price (its preferred supplier's), like the dashboard
#   "last"     the price on its latest received order line
#   "average"  the quantity-weighted average over its received order lines
# A part never received at a price falls back to its current price; one with no
# price at all is valued at zero and counted as unpriced.
class StockValuation
  METHODS = %w[current last average].freeze

  # +source+: "purchase" (from received orders), "current" (the part's price) or nil (no price).
  Row = Struct.new(:part, :quantity, :unit_value, :source, keyword_init: true) do
    def value
      unit_value ? quantity * unit_value : 0
    end
  end

  attr_reader :organization, :valuation_method

  def initialize(organization, method: nil)
    @organization = organization
    @valuation_method = METHODS.include?(method.to_s) ? method.to_s : "current"
  end

  # One row per part with stock on hand, most valuable first.
  def rows
    @rows ||= begin
      quantities = organization.parts.joins(:part_storages).group("parts.id")
        .having("SUM(part_storages.quantity) > 0").sum("part_storages.quantity")
      purchased = purchase_prices(quantities.keys)

      organization.parts.where(id: quantities.keys).includes(:category).map do |part|
        price, source =
          if purchased[part.id] then [ purchased[part.id], "purchase" ]
          elsif part.unit_price then [ part.unit_price, "current" ]
          else [ nil, nil ]
          end
        Row.new(part: part, quantity: quantities[part.id], unit_value: price, source: source)
      end.sort_by { |row| [ -row.value, row.part.reference.to_s.downcase ] }
    end
  end

  def total
    rows.sum(&:value)
  end

  def unpriced_rows
    rows.select { |row| row.unit_value.nil? }
  end

  # [{ category:, value:, parts: }] most valuable first.
  def by_category
    rows.group_by { |row| row.part.category }.map do |category, category_rows|
      { category: category, value: category_rows.sum(&:value), parts: category_rows.size }
    end.sort_by { |entry| [ -entry[:value], entry[:category]&.name.to_s.downcase ] }
  end

  # [{ zone:, value:, parts: }] per top-level zone, most valuable first. Each
  # stock row is valued at its part's unit value.
  def by_root_zone
    unit_values = rows.to_h { |row| [ row.part.id, row.unit_value || 0 ] }
    zones = StorageLocation.full_path_cache(organization.storage_locations)
    totals = Hash.new { |hash, key| hash[key] = { value: 0, parts: Set.new } }

    PartStorage.where(part_id: unit_values.keys).where("quantity > 0").pluck(:part_id, :storage_location_id, :quantity).each do |part_id, zone_id, quantity|
      root = zones[zone_id]
      root = zones[root.parent_id] while root&.parent_id && zones[root.parent_id]
      next unless root

      totals[root][:value] += quantity * unit_values[part_id]
      totals[root][:parts] << part_id
    end

    totals.map { |zone, entry| { zone: zone, value: entry[:value], parts: entry[:parts].size } }
      .sort_by { |entry| [ -entry[:value], entry[:zone].name.downcase ] }
  end

  private

  # part id => unit price from received order lines, per the method.
  def purchase_prices(part_ids)
    return {} if valuation_method == "current" || part_ids.empty?

    lines = OrderLine.joins(:order)
      .where(orders: { organization_id: organization.id, status: "received" }, part_id: part_ids)
      .where.not(unit_price: nil)

    if valuation_method == "average"
      quantities = lines.group(:part_id).sum(:quantity)
      spent = lines.group(:part_id).sum("order_lines.quantity * order_lines.unit_price")
      quantities.to_h { |part_id, quantity| [ part_id, (BigDecimal(spent[part_id].to_s) / quantity).round(4) ] }
    else
      lines.order(Arel.sql("COALESCE(orders.ordered_at, DATE(orders.created_at))"), "order_lines.id")
        .pluck(:part_id, :unit_price).to_h
    end
  end
end

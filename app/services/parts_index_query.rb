# frozen_string_literal: true

# Search, category, facet filters, sort and pagination for the inventory list
# (PartsController#index). The page only receives one page of fully serialized
# parts; filtering and the facet counts run here over a light row per part
# (a handful of plucked columns, no images or tags), so the payload no longer
# grows with the inventory.
#
# Semantics match what the page used to do in the browser: search is a
# case-insensitive substring match over the reference fields, category,
# footprint and location names; facet counts are taken after search +
# category, so each chip shows how many parts it would leave.
class PartsIndexQuery
  PAGE_SIZE = 50
  SORTS = %w[ref crit qtyDesc qtyAsc priceDesc].freeze
  STOCK_STATUSES = {
    "out" => "Out of stock",
    "low" => "Low stock",
    "ok" => "In stock"
  }.freeze

  Row = Struct.new(
    :id, :name, :mpn, :sku, :ipn, :manufacturer, :value, :package_type,
    :category_id, :category_name, :footprint_name, :supplier_name,
    :location_names, :total_quantity, :min_stock_threshold, :unit_price,
    keyword_init: true
  ) do
    def reference
      mpn.presence || sku.presence || name
    end

    def stock_status
      return "out" if total_quantity.zero?
      return "low" if total_quantity < min_stock_threshold.to_i

      "ok"
    end

    def haystack
      [ name, mpn, sku, ipn, manufacturer, value, category_name, footprint_name, *location_names ]
        .compact_blank.join(" ").downcase
    end
  end

  attr_reader :search, :category_id, :statuses, :packages, :footprints, :suppliers, :sort

  def initialize(organization, params = {})
    @organization = organization
    @search = params[:search].to_s.strip
    @category_id = params[:category].presence&.to_i
    @statuses = list_param(params[:status]) & STOCK_STATUSES.keys
    @packages = list_param(params[:package])
    @footprints = list_param(params[:footprint])
    @suppliers = list_param(params[:supplier])
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "ref"
    @requested_page = params[:page].to_i
  end

  def filters
    {
      search: search,
      category: category_id,
      status: statuses,
      package: packages,
      footprint: footprints,
      supplier: suppliers,
      sort: sort
    }
  end

  # Every part of the organization, as light rows in alphabetical order.
  def rows
    @rows ||= load_rows
  end

  def total_count
    rows.size
  end

  # Parts left after search + category: the base for the facet counts.
  def searched
    @searched ||= rows.select do |row|
      (category_id.nil? || row.category_id == category_id) &&
        (search.empty? || row.haystack.include?(search.downcase))
    end
  end

  # Parts matching every filter, sorted.
  def matching
    @matching ||= sort_rows(searched.select do |row|
      (statuses.empty? || statuses.include?(row.stock_status)) &&
        (packages.empty? || packages.include?(row.package_type)) &&
        (footprints.empty? || footprints.include?(row.footprint_name)) &&
        (suppliers.empty? || suppliers.include?(row.supplier_name))
    end)
  end

  def matching_ids
    matching.map(&:id)
  end

  def total_units
    matching.sum(&:total_quantity)
  end

  def page_count
    [ (matching.size.to_f / PAGE_SIZE).ceil, 1 ].max
  end

  # 1-based, clamped to the last page so a filter change can't leave the list
  # on an empty page.
  def page
    @requested_page.clamp(1, page_count)
  end

  def page_ids
    matching.slice((page - 1) * PAGE_SIZE, PAGE_SIZE).map(&:id)
  end

  def pagination
    { page: page, page_count: page_count, page_size: PAGE_SIZE, total: matching.size }
  end

  def facets
    {
      categories: category_chips,
      status: STOCK_STATUSES.filter_map do |key, label|
        count = searched.count { |row| row.stock_status == key }
        { value: key, label: label, count: count } if count.positive?
      end,
      package: counts_by(&:package_type),
      footprint: counts_by(&:footprint_name),
      supplier: counts_by(&:supplier_name)
    }
  end

  private

  attr_reader :organization

  def list_param(value)
    Array(value).map(&:to_s).compact_blank.uniq
  end

  # Category chips count every part, not just the filtered ones, so switching
  # category never hides the others.
  def category_chips
    rows.select(&:category_id).group_by(&:category_id).map do |id, group|
      { id: id, name: group.first.category_name, count: group.size }
    end.sort_by { |chip| chip[:name].to_s.downcase }
  end

  def counts_by(&key)
    searched.filter_map(&key).tally.sort_by { |value, _| value.downcase }
      .map { |value, count| { value: value, label: value, count: count } }
  end

  def sort_rows(list)
    indexed = list.each_with_index
    sorted = case sort
    when "crit" then indexed.sort_by { |row, i| [ row.total_quantity.to_f / [ row.min_stock_threshold.to_i, 1 ].max, i ] }
    when "qtyDesc" then indexed.sort_by { |row, i| [ -row.total_quantity, i ] }
    when "qtyAsc" then indexed.sort_by { |row, i| [ row.total_quantity, i ] }
    when "priceDesc" then indexed.sort_by { |row, i| [ -row.unit_price.to_f, i ] }
    else indexed.sort_by { |row, i| [ row.reference.downcase, i ] }
    end
    sorted.map(&:first)
  end

  def load_rows
    parts = organization.parts.alphabetical
    part_ids = parts.select(:id)

    categories = organization.categories.pluck(:id, :name).to_h
    footprints = organization.footprints.pluck(:id, :name).to_h
    quantities = PartStorage.where(part_id: part_ids).group(:part_id).sum(:quantity)
    locations = PartStorage.joins(:storage_location).where(part_id: part_ids)
      .order("part_storages.id").pluck(:part_id, "storage_locations.name")
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    preferred = PartSupplier.preferred.joins(:supplier).where(part_id: part_ids)
      .pluck(:part_id, "suppliers.name").to_h

    parts.pluck(
      :id, :name, :mpn, :sku, :ipn, :manufacturer, :value, :package_type,
      :category_id, :footprint_id, :min_stock_threshold, :unit_price
    ).map do |id, name, mpn, sku, ipn, manufacturer, value, package_type, category_id, footprint_id, threshold, price|
      Row.new(
        id: id, name: name, mpn: mpn, sku: sku, ipn: ipn, manufacturer: manufacturer,
        value: value, package_type: package_type,
        category_id: category_id, category_name: categories[category_id],
        footprint_name: footprints[footprint_id],
        supplier_name: preferred[id],
        location_names: locations.fetch(id, []),
        total_quantity: quantities.fetch(id, 0),
        min_stock_threshold: threshold,
        unit_price: price
      )
    end
  end
end

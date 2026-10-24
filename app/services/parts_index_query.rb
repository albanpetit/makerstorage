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
#
# Parameter filters (`param[<definition id>][min|max]` for number parameters,
# `param[<id>][values][]` for text ones) keep the parts whose value is in the
# range or the list. Bounds are typed like part values ("10k", "1/4W") and
# read in the parameter's unit (ParameterValue); one that doesn't read as a
# number is ignored and reported as invalid.
class PartsIndexQuery
  PAGE_SIZE = 50
  SORTS = %w[ref crit qtyDesc qtyAsc priceDesc].freeze
  # Labels under stock_statuses.* in config/locales.
  STOCK_STATUSES = %w[out low ok].freeze

  Row = Struct.new(
    :id, :name, :mpn, :sku, :ipn, :manufacturer, :value, :package_type,
    :category_id, :category_name, :footprint_name, :supplier_name,
    :location_names, :total_quantity, :min_stock_threshold, :unit_price,
    # Parameter definition id => [value as typed, numeric value].
    :parameters,
    keyword_init: true
  ) do
    def reference
      mpn.presence || sku.presence || name
    end

    def stock_status
      return "out" if total_quantity.zero?
      return "low" if total_quantity < (min_stock_threshold || 0)

      "ok"
    end

    def haystack
      [ name, mpn, sku, ipn, manufacturer, value, category_name, footprint_name, *location_names, *parameters.values.map(&:first) ]
        .compact_blank.join(" ").downcase
    end
  end

  attr_reader :search, :category_id, :statuses, :packages, :footprints, :suppliers, :sort

  def initialize(organization, params = {})
    @organization = organization
    @search = params[:search].to_s.strip
    @category_id = params[:category].presence&.to_i
    @statuses = list_param(params[:status]) & STOCK_STATUSES
    @packages = list_param(params[:package])
    @footprints = list_param(params[:footprint])
    @suppliers = list_param(params[:supplier])
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "ref"
    @requested_page = params[:page].to_i
    @parameter_params = hash_param(params[:param]).presence || parameters_list_param(params[:parameters])
  end

  def filters
    {
      search: search,
      category: category_id,
      status: statuses,
      package: packages,
      footprint: footprints,
      supplier: suppliers,
      parameters: parameter_filters.map do |filter|
        definition = filter[:definition]
        {
          id: definition.id, name: definition.name, unit: definition.unit, value_type: definition.value_type,
          min: filter[:min_text], max: filter[:max_text], values: filter[:values],
          min_display: definition.display(filter[:min_text], filter[:min]),
          max_display: definition.display(filter[:max_text], filter[:max]),
          invalid: filter[:invalid]
        }
      end,
      sort: sort
    }
  end

  # The parameters to show as list columns: the selected category's template.
  def parameter_columns
    return [] if category_id.nil?

    template = Category.parameter_templates(organization)[category_id] || []
    template.filter_map { |id| definitions[id] }.map do |definition|
      { id: definition.id, name: definition.name, unit: definition.unit }
    end
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
        (suppliers.empty? || suppliers.include?(row.supplier_name)) &&
        parameter_filters.all? { |filter| parameter_match?(row, filter) }
    end)
  end

  def matching_ids
    matching.map(&:id)
  end

  def total_units
    Quantity.sum(matching.map(&:total_quantity))
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
      status: STOCK_STATUSES.filter_map do |key|
        count = searched.count { |row| row.stock_status == key }
        { value: key, label: I18n.t("stock_statuses.#{key}"), count: count } if count.positive?
      end,
      package: counts_by(&:package_type),
      footprint: counts_by(&:footprint_name),
      supplier: counts_by(&:supplier_name),
      parameters: parameter_facets
    }
  end

  private

  attr_reader :organization

  def list_param(value)
    Array(value).map(&:to_s).compact_blank.uniq
  end

  def hash_param(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value.is_a?(Hash) ? value : {}
  end

  # The `filters.parameters` list the page sends back for an export (the
  # shape #filters returns), as `param` reads.
  def parameters_list_param(value)
    return {} unless value.is_a?(Array)

    value.filter_map do |filter|
      filter = hash_param(filter)
      [ filter["id"].to_s, filter.slice("min", "max", "values") ] if filter["id"].present?
    end.to_h
  end

  def definitions
    @definitions ||= organization.parameter_definitions.index_by(&:id)
  end

  # The parameter filters asked for, with their bounds read in the
  # parameter's unit. Unknown parameters and empty filters are left out.
  def parameter_filters
    @parameter_filters ||= @parameter_params.filter_map do |id, filter|
      definition = definitions[id.to_s.to_i]
      filter = hash_param(filter)
      next unless definition

      if definition.number?
        min_text = filter["min"].to_s.strip.presence
        max_text = filter["max"].to_s.strip.presence
        next if min_text.nil? && max_text.nil?

        min = min_text && definition.parse(min_text)
        max = max_text && definition.parse(max_text)
        { definition: definition, min_text: min_text, max_text: max_text, min: min, max: max,
          values: [], invalid: (min_text && min.nil?) || (max_text && max.nil?) || false }
      else
        values = list_param(filter["values"])
        next if values.empty?

        { definition: definition, values: values, invalid: false }
      end
    end
  end

  # Floating-point slack when comparing to a bound: "10k" typed in a filter
  # and "10 kΩ" typed on a part are the same value.
  EPSILON = 1e-9

  def parameter_match?(row, filter)
    value, numeric = row.parameters[filter[:definition].id]
    return false if value.nil?

    if filter[:definition].number?
      return false if numeric.nil?

      min, max = filter.values_at(:min, :max)
      (min.nil? || numeric >= min - (min.abs * EPSILON)) && (max.nil? || numeric <= max + (max.abs * EPSILON))
    else
      filter[:values].any? { |wanted| wanted.casecmp?(value) }
    end
  end

  # The parameters the searched parts have, with how many parts have each:
  # the observed range for number parameters, the values for text ones.
  def parameter_facets
    values_by_id = Hash.new { |hash, id| hash[id] = [] }
    searched.each { |row| row.parameters.each { |id, pair| values_by_id[id] << pair } }
    template = category_id ? (Category.parameter_templates(organization)[category_id] || []) : []

    values_by_id.filter_map do |id, pairs|
      definition = definitions[id] or next
      facet = { id: id, name: definition.name, unit: definition.unit, value_type: definition.value_type,
                count: pairs.size, in_template: template.include?(id) }
      if definition.number?
        numbers = pairs.filter_map(&:last)
        facet.merge(min_display: definition.display(nil, numbers.min), max_display: definition.display(nil, numbers.max), values: [])
      else
        values = pairs.map(&:first).group_by(&:downcase).values
          .map { |same| { value: same.first, label: same.first, count: same.size } }
          .sort_by { |option| option[:label].downcase }
        facet.merge(values: values)
      end
    end.sort_by { |facet| [ facet[:in_template] ? 0 : 1, facet[:name].downcase ] }
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
    when "crit" then indexed.sort_by { |row, i| [ row.total_quantity.to_f / [ row.min_stock_threshold.to_f, 1 ].max, i ] }
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
    parameters = PartParameter.where(part_id: part_ids)
      .pluck(:part_id, :parameter_definition_id, :value, :numeric_value)
      .group_by(&:first).transform_values { |rows| rows.to_h { |_, id, value, numeric| [ id, [ value, numeric ] ] } }

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
        unit_price: price,
        parameters: parameters.fetch(id, {})
      )
    end
  end
end

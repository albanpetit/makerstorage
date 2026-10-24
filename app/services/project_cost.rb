# frozen_string_literal: true

# What +quantity+ copies of a project cost, from the prices already on file
# (project page cost card, its CSV and MCP get_project_cost).
#
# Each matched part's need for that many copies is first taken from the stock
# the project can count on (Project#available_for, so projects that reserved
# before it come first), and the rest is bought:
#   - stock is valued at the part's unit price (its cost basis, as on the Stock
#     value page), else its preferred or cheapest supplier price;
#   - what is bought costs the supplier's price break for the quantity bought:
#     the preferred supplier's link, else the link that is cheapest at that
#     quantity, else the part's unit price.
# A part with no price is listed as unpriced instead of counting as free, and
# lines matched to no part (free text) can't be priced at all: an estimate
# with either is incomplete, its totals a lower bound. Open orders aren't
# subtracted (what they bring is still paid for) and minimum order quantities
# aren't applied: below the first break the plain unit price is used, like an
# order line (PartSupplier#unit_price_for).
class ProjectCost
  DEFAULT_QUANTITIES = [ 1, 10, 100 ].freeze
  MAX_QUANTITY = 100_000

  # One matched part for +quantity+ copies. Prices are nil when unknown.
  Row = Struct.new(:part, :required, :from_stock, :to_buy, :stock_unit_price, :buy_unit_price, :supplier, keyword_init: true) do
    def stock_value
      from_stock.positive? && stock_unit_price ? from_stock * stock_unit_price : 0
    end

    def purchase_cost
      to_buy.positive? && buy_unit_price ? to_buy * buy_unit_price : 0
    end

    def cost
      stock_value + purchase_cost
    end

    # Every unit it needs has a price.
    def priced?
      (from_stock.zero? || !stock_unit_price.nil?) && (to_buy.zero? || !buy_unit_price.nil?)
    end
  end

  Estimate = Struct.new(:quantity, :rows, :unmatched_lines, keyword_init: true) do
    def stock_value
      rows.sum(&:stock_value)
    end

    def purchase_cost
      rows.sum(&:purchase_cost)
    end

    def total
      stock_value + purchase_cost
    end

    def per_unit
      total.to_d / quantity
    end

    def unpriced_rows
      rows.reject(&:priced?)
    end

    # Every line is matched and priced: the totals are the full cost.
    def complete?
      unpriced_rows.empty? && unmatched_lines.empty?
    end
  end

  # The default quantities plus +extra+ when it's a valid quantity, sorted.
  def self.quantities(extra = nil)
    extra = Integer(extra.to_s, exception: false)
    extra = nil unless extra&.between?(1, MAX_QUANTITY)
    (DEFAULT_QUANTITIES + [ extra ]).compact.uniq.sort
  end

  attr_reader :project

  # Preload `project_lines: { part: [ :part_storages, { part_suppliers: :supplier } ] }`
  # to avoid N+1 queries.
  def initialize(project)
    @project = project
  end

  def estimates(quantities = DEFAULT_QUANTITIES)
    quantities.map { |quantity| estimate(quantity) }
  end

  def estimate(quantity)
    quantity = quantity.to_i.clamp(1, MAX_QUANTITY)
    rows = project.required_by_part(kits: quantity).map do |part, required|
      from_stock = [ required, project.available_for(part) ].min
      to_buy = Quantity.sum(required, -from_stock)
      link = purchase_link(part, [ to_buy, 1 ].max)

      Row.new(
        part: part,
        required: required,
        from_stock: from_stock,
        to_buy: to_buy,
        stock_unit_price: part.unit_price || link&.unit_price,
        buy_unit_price: link&.unit_price_for(to_buy) || part.unit_price,
        supplier: link&.supplier
      )
    end

    Estimate.new(
      quantity: quantity,
      rows: rows.sort_by { |row| [ -row.cost, row.part.reference.to_s.downcase ] },
      unmatched_lines: project.unmatched_lines
    )
  end

  private

  # The supplier link +quantity+ would be bought from: the preferred one when
  # it has a price, else the one cheapest at that quantity.
  def purchase_link(part, quantity)
    links = part.part_suppliers.to_a.reject { |link| link.unit_price_for(quantity).nil? }
    links.find(&:is_preferred) || links.min_by { |link| link.unit_price_for(quantity) }
  end
end

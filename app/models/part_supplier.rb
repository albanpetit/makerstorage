# frozen_string_literal: true

class PartSupplier < ApplicationRecord
  # Distributors publish a handful of breaks (1, 10, 100, 1000, …); more than
  # this is a paste gone wrong.
  MAX_PRICE_BREAKS = 20

  # Associations
  belongs_to :part
  belongs_to :supplier

  # Validations
  validates :supplier_id, uniqueness: { scope: :part_id, message: "is already linked to this part" }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_INTEGER }, allow_nil: true
  validates :url, format: { with: HTTP_URL_FORMAT }, allow_blank: true
  validate :supplier_must_belong_to_same_organization
  validate :price_breaks_must_be_valid

  # Scopes
  scope :preferred, -> { where(is_preferred: true) }
  scope :with_price, -> { where.not(unit_price: nil) }
  scope :by_price, -> { order(:unit_price) }

  # Callbacks
  before_validation :normalize_price_breaks
  before_save :ensure_single_preferred
  # Keep the part's cost basis (Part#unit_price) mirroring its preferred
  # supplier's price whenever a link is added, repriced, re-preferred, or removed.
  after_save :sync_part_unit_price
  after_destroy :sync_part_unit_price

  # Price breaks as sorted [{ "quantity" => Integer, "unit_price" => BigDecimal }].
  def price_break_rows
    Array(price_breaks).filter_map do |row|
      quantity = Integer(row["quantity"].to_s, exception: false)
      price = BigDecimal(row["unit_price"].to_s, exception: false)
      { "quantity" => quantity, "unit_price" => price } if quantity && price
    end
  end

  # Unit price when buying +quantity+: the break for the largest quantity not
  # above it. Below the first break (or with no breaks) it's the plain unit
  # price, else the first break's (a minimum order quantity).
  def unit_price_for(quantity)
    rows = price_break_rows
    return unit_price if rows.empty? || quantity.nil?

    applicable = rows.select { |row| row["quantity"] <= quantity.to_i }.last
    applicable ? applicable["unit_price"] : (unit_price || rows.first["unit_price"])
  end

  # Breaks as { quantity:, unit_price: } numbers for JSON payloads.
  def price_breaks_for_json
    price_break_rows.map { |row| { quantity: row["quantity"], unit_price: row["unit_price"].to_f } }
  end

  private

  # Accepts rows keyed by strings or symbols, numbers or numeric strings
  # (decimal comma too), drops blank rows, keeps one price per quantity (the
  # last given), and sorts by quantity. Unreadable rows are kept as given so
  # the validation can name them.
  def normalize_price_breaks
    rows = Array(price_breaks).filter_map do |row|
      row = row.to_h.stringify_keys if row.respond_to?(:to_h)
      next unless row.is_a?(Hash)

      quantity = row["quantity"].to_s.strip
      price = row["unit_price"].to_s.strip.tr(",", ".")
      next if quantity.empty? && price.empty?

      parsed_price = BigDecimal(price, exception: false)
      { "quantity" => Integer(quantity, exception: false) || quantity,
        "unit_price" => parsed_price ? parsed_price.round(4).to_s("F") : price }
    end
    readable, unreadable = rows.partition { |row| row["quantity"].is_a?(Integer) }
    readable = readable.reverse.uniq { |row| row["quantity"] }.sort_by { |row| row["quantity"] }
    self.price_breaks = readable + unreadable
    # A link filled only with breaks still gets a unit price (the first break's).
    first_price = BigDecimal(readable.first&.dig("unit_price").to_s, exception: false)
    self.unit_price = first_price if unit_price.nil? && first_price
  end

  def price_breaks_must_be_valid
    rows = Array(price_breaks)
    return errors.add(:price_breaks, :too_many_price_breaks, count: MAX_PRICE_BREAKS) if rows.size > MAX_PRICE_BREAKS

    valid = rows.all? do |row|
      quantity = row["quantity"]
      price = BigDecimal(row["unit_price"].to_s, exception: false)
      quantity.is_a?(Integer) && quantity.positive? && quantity <= MAX_INTEGER && price && price >= 0
    end
    errors.add(:price_breaks, :invalid_price_breaks) unless valid
  end

  def sync_part_unit_price
    part.sync_unit_price_from_preferred!
  end

  def supplier_must_belong_to_same_organization
    return unless part && supplier

    if supplier.organization_id != part.organization_id
      errors.add(:supplier, :same_organization)
    end
  end

  # Ensure only one preferred supplier per part
  def ensure_single_preferred
    return unless is_preferred? && is_preferred_changed?

    PartSupplier.where(part_id: part_id, is_preferred: true)
                .where.not(id: id)
                .update_all(is_preferred: false)
  end
end

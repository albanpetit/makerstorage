class Part < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :category
  belongs_to :footprint, optional: true

  has_many :part_storages, dependent: :destroy
  has_many :storage_locations, through: :part_storages

  has_many :stock_movements, dependent: :restrict_with_error

  has_many :part_tags, dependent: :destroy
  has_many :tags, through: :part_tags

  has_many :part_suppliers, dependent: :destroy
  has_many :suppliers, through: :part_suppliers
  accepts_nested_attributes_for :part_suppliers, allow_destroy: true, reject_if: :all_blank

  has_many :purchase_lines, dependent: :restrict_with_error
  has_many :purchases, through: :purchase_lines

  # Active Storage for images and datasheets
  has_many_attached :images
  has_one_attached :datasheet

  # Constants
  STATUSES = %w[active discontinued obsolete].freeze
  UNITS = %w[piece meter roll lot].freeze

  # Callbacks - convert empty strings to nil for unique indexed fields
  before_validation :normalize_blank_values
  # Assign the internal part number from the org's IPN config once the part is
  # actually being persisted (see #assign_ipn).
  before_create :assign_ipn

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :mpn, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :sku, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :barcode, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :ipn, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :unit, presence: true, inclusion: { in: UNITS }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :target_stock, numericality: { greater_than: 0 }, allow_nil: true
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # Hotlinked supplier image (e.g. Mouser, whose CDN blocks server-side download);
  # rendered directly in an <img>, so only allow http(s) URLs.
  validates :image_source_url, format: { with: %r{\Ahttps?://[^\s]+\z}i }, allow_blank: true
  validate :category_must_belong_to_same_organization
  validate :footprint_must_belong_to_same_organization

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :discontinued, -> { where(status: "discontinued") }
  scope :obsolete, -> { where(status: "obsolete") }
  scope :rohs_compliant, -> { where(rohs_compliant: true) }

  scope :by_category, ->(category_id) { where(category_id: category_id) }
  scope :by_footprint, ->(footprint_id) { where(footprint_id: footprint_id) }
  scope :by_manufacturer, ->(manufacturer) { where(manufacturer: manufacturer) }
  scope :by_value, ->(value) { where(value: value) }

  # Low stock: total quantity < minimum threshold
  scope :low_stock, -> {
    joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) < parts.min_stock_threshold")
  }

  # Critical stock: total quantity = 0
  scope :out_of_stock, -> {
    left_joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) = 0")
  }

  # Sufficient stock
  scope :sufficient_stock, -> {
    joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) >= parts.min_stock_threshold")
  }

  # Extended search. Escape LIKE wildcards (%, _, \) in the user's query so they
  # match literally rather than acting as wildcards, and declare the escape char.
  scope :search, ->(query) {
    q = "%#{sanitize_sql_like(query)}%"
    where(
      "parts.name LIKE :q ESCAPE '\\' OR parts.mpn LIKE :q ESCAPE '\\' OR " \
      "parts.description LIKE :q ESCAPE '\\' OR parts.sku LIKE :q ESCAPE '\\' OR " \
      "parts.manufacturer LIKE :q ESCAPE '\\' OR parts.value LIKE :q ESCAPE '\\' OR " \
      "parts.barcode LIKE :q ESCAPE '\\'",
      q: q
    )
  }

  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods - Stock
  def total_quantity
    part_storages.sum(:quantity)
  end

  def low_stock?
    total_quantity < min_stock_threshold
  end

  def out_of_stock?
    total_quantity.zero?
  end

  def stock_status
    return :out_of_stock if out_of_stock?
    return :low_stock if low_stock?
    :sufficient
  end

  def quantity_to_order
    return 0 if target_stock.nil?
    [ target_stock - total_quantity, 0 ].max
  end

  def stock_status_badge
    case stock_status
    when :out_of_stock
      { label: "Out of stock", color: "red" }
    when :low_stock
      { label: "Low stock", color: "orange" }
    else
      { label: "OK", color: "green" }
    end
  end

  # Methods - Status
  def active?
    status == "active"
  end

  def discontinued?
    status == "discontinued"
  end

  def obsolete?
    status == "obsolete"
  end

  def status_badge
    case status
    when "active"
      { label: "Active", color: "green" }
    when "discontinued"
      { label: "Discontinued", color: "orange" }
    when "obsolete"
      { label: "Obsolete", color: "red" }
    end
  end

  # Methods - References
  def full_reference
    refs = []
    refs << "SKU: #{sku}" if sku.present?
    refs << "MPN: #{mpn}" if mpn.present?
    refs << "Barcode: #{barcode}" if barcode.present?
    refs.join(" | ")
  end

  # Methods - Suppliers
  def preferred_supplier
    part_suppliers.find_by(is_preferred: true)&.supplier
  end

  def preferred_part_supplier
    part_suppliers.find_by(is_preferred: true)
  end

  # Mirrors unit_price (the part's cost basis for stock valuation) onto the
  # preferred supplier's price. Called from PartSupplier when links change so
  # the two never drift. Leaves a manually-entered price untouched when there is
  # no preferred supplier price to sync from.
  def sync_unit_price_from_preferred!
    price = preferred_part_supplier&.unit_price
    return if price.nil? || unit_price == price

    update_column(:unit_price, price)
  end

  # Methods - Technical specs
  def technical_specs
    specs = {}
    specs[:value] = value if value.present?
    specs[:tolerance] = tolerance if tolerance.present?
    specs[:power_rating] = power_rating if power_rating.present?
    specs[:voltage_rating] = voltage_rating if voltage_rating.present?
    specs[:package_type] = package_type if package_type.present?
    specs
  end

  # Methods - Attachments
  def has_datasheet?
    datasheet.attached?
  end

  def has_images?
    images.attached?
  end

  private

  # Convert blank strings to nil for unique indexed fields
  def normalize_blank_values
    self.sku = nil if sku.blank?
    self.mpn = nil if mpn.blank?
    self.barcode = nil if barcode.blank?
    self.ipn = nil if ipn.blank?
  end

  # Stamp the internal part number from the organization's IPN engine. In
  # `manual` mode the operator types the reference (or leaves it blank), so we
  # never auto-generate; an explicitly supplied `ipn` in any mode is also left
  # as-is. Otherwise we draw the next reference from the org config and advance
  # its shared counter.
  #
  # A drawn reference can already be taken — a random-mode collision, or a
  # counter the operator manually rewound over existing numbers — so we redraw
  # from the next seed until we find a free one (bounded, so a misconfiguration
  # can't spin forever). This is the "collision triggers a fresh draw" behavior
  # the settings UI promises.
  #
  # The whole thing runs under a row lock so concurrent part creations in the
  # same org can't consume the same sequence number, and it sits in the create
  # transaction so a failed insert rolls the counter advance back too.
  def assign_ipn
    return if ipn.present? || organization.nil?
    return if organization.ipn_generation_mode == "manual"

    organization.with_lock do
      sequence = organization.ipn_next_sequence
      candidate = organization.next_ipn(category_code: category&.code, sequence: sequence)

      attempts = 0
      while organization.parts.exists?(ipn: candidate) && attempts < 100
        sequence += 1
        candidate = organization.next_ipn(category_code: category&.code, sequence: sequence)
        attempts += 1
      end

      self.ipn = candidate
      organization.update_column(:ipn_next_sequence, sequence + 1)
    end
  end

  def category_must_belong_to_same_organization
    if category.present? && category.organization_id != organization_id
      errors.add(:category, "must belong to the same organization")
    end
  end

  def footprint_must_belong_to_same_organization
    if footprint.present? && footprint.organization_id != organization_id
      errors.add(:footprint, "must belong to the same organization")
    end
  end
end

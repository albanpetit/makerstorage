class Part < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :category
  belongs_to :footprint, optional: true
  belongs_to :preferred_supplier, class_name: "Supplier", optional: true

  has_many :part_storages, dependent: :destroy
  # has_many :storage_locations, through: :part_storages

  has_many :part_tags, dependent: :destroy
  has_many :tags, through: :part_tags

  has_many :purchase_lines, dependent: :restrict_with_error

  # Active Storage for images and datasheets
  has_many_attached :images
  has_one_attached :datasheet

  # Constants
  STATUSES = %w[active discontinued obsolete].freeze

  # Callbacks - convert empty strings to nil for unique indexed fields
  before_validation :normalize_blank_values

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :mpn, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :sku, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :barcode, uniqueness: true, allow_blank: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_stock_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :target_stock, numericality: { greater_than: 0 }, allow_nil: true
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :category_must_belong_to_same_organization
  validate :footprint_must_belong_to_same_organization
  validate :supplier_must_belong_to_same_organization

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

  # Extended search
  scope :search, ->(query) {
    where("parts.name ILIKE ? OR parts.mpn ILIKE ? OR parts.description ILIKE ? OR parts.sku ILIKE ? OR parts.manufacturer ILIKE ? OR parts.value ILIKE ? OR parts.barcode ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  }

  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods - Stock
  # def total_quantity
  #   part_storages.sum(:quantity)
  # end

  # def low_stock?
  #   total_quantity < min_stock_threshold
  # end

  # def out_of_stock?
  #   total_quantity.zero?
  # end

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
    refs << "Supplier SKU: #{supplier_sku}" if supplier_sku.present?
    refs << "Barcode: #{barcode}" if barcode.present?
    refs.join(" | ")
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

  def supplier_must_belong_to_same_organization
    if preferred_supplier.present? && preferred_supplier.organization_id != organization_id
      errors.add(:preferred_supplier, "must belong to the same organization")
    end
  end
end

class Purchase < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :supplier
  has_many :purchase_lines, dependent: :destroy
  has_many :parts, through: :purchase_lines

  # Constants
  STATUSES = %w[pending shipped received cancelled].freeze

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :supplier_must_belong_to_same_organization

  # Scopes
  scope :recent, -> { order(ordered_at: :desc) }
  scope :of_status, ->(status) { where(status: status) }
  scope :pending, -> { where(status: "pending") }
  scope :received, -> { where(status: "received") }

  # Methods
  def pending?
    status == "pending"
  end

  def shipped?
    status == "shipped"
  end

  def received?
    status == "received"
  end

  def cancelled?
    status == "cancelled"
  end

  def computed_total
    purchase_lines.sum("quantity * unit_price")
  end

  private

  def supplier_must_belong_to_same_organization
    if supplier.present? && supplier.organization_id != organization_id
      errors.add(:supplier, "must belong to the same organization")
    end
  end
end

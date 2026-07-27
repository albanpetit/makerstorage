class OrderLine < ApplicationRecord
  # Associations
  belongs_to :order
  belongs_to :part
  # Target storage zones for the line's received quantity. Either empty (falls
  # back to the part's first location on receipt) or summing exactly to the
  # line quantity — the write paths keep that invariant.
  has_many :allocations, class_name: "OrderLineAllocation", dependent: :destroy

  # Validations
  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Methods
  def subtotal
    return nil if unit_price.nil?
    quantity * unit_price
  end

  def allocated_quantity
    allocations.sum(&:quantity)
  end

  # True when the line's received quantity is fully distributed across zones.
  def fully_allocated?
    allocations.any? && allocated_quantity == quantity
  end
end

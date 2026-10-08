class OrderLine < ApplicationRecord
  # Associations
  belongs_to :order
  belongs_to :part
  # Target storage zones for the line's received quantity. Either empty (falls
  # back to the part's first location on receipt) or summing exactly to the
  # line quantity — enforced below by dropping a split the moment the quantity
  # changes, whichever code path changed it.
  has_many :allocations, class_name: "OrderLineAllocation", dependent: :destroy

  # Validations
  validates :quantity, numericality: { greater_than: 0, less_than_or_equal_to: MAX_INTEGER, only_integer: true }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :part_must_belong_to_same_organization

  # Callbacks
  # A split sized for the old quantity no longer adds up; keeping it would credit
  # only the old amount on receipt. The line reverts to the fallback location
  # until a new split is set (which callers may do right after, in the same
  # transaction).
  after_update :clear_stale_allocations, if: :saved_change_to_quantity?

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

  private

  def part_must_belong_to_same_organization
    if part.present? && order.present? && part.organization_id != order.organization_id
      errors.add(:part, "must belong to the same organization")
    end
  end

  def clear_stale_allocations
    allocations.destroy_all
  end
end

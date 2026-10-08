class OrderLineAllocation < ApplicationRecord
  # A slice of an order line's received quantity destined for one storage zone.
  # Lets a received line be split across several zones (e.g. 50 in Drawer A,
  # 50 in Drawer B).

  # Associations
  belongs_to :order_line
  belongs_to :storage_location

  # Validations
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INTEGER }
  validate :storage_location_must_belong_to_same_organization

  private

  def storage_location_must_belong_to_same_organization
    return unless order_line&.part && storage_location

    if storage_location.organization_id != order_line.part.organization_id
      errors.add(:storage_location, "must belong to the same organization")
    end
  end
end

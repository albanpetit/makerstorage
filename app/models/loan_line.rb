# One part on a loan: how many were lent, from which zone, and how many came
# back or were written off. The zone may be cleared later (zone deleted); it's
# only the default target for returns.
class LoanLine < ApplicationRecord
  # Associations
  belongs_to :loan, inverse_of: :loan_lines
  belongs_to :part
  belongs_to :storage_location, optional: true

  # In the part's unit (see Quantity).
  attribute :quantity, Quantity::Type.new
  attribute :returned_quantity, Quantity::Type.new
  attribute :lost_quantity, Quantity::Type.new

  # Validations
  validates :quantity, quantity: { greater_than: 0, unit_of: :part }
  validates :returned_quantity, :lost_quantity, quantity: { greater_than_or_equal_to: 0, unit_of: :part }
  validates :storage_location, presence: true, on: :create
  validate :settled_quantities_within_quantity
  validate :part_must_belong_to_same_organization
  validate :storage_location_must_belong_to_same_organization

  # Scopes
  scope :outstanding, -> { where("loan_lines.quantity > loan_lines.returned_quantity + loan_lines.lost_quantity") }

  # Methods
  def outstanding_quantity
    Quantity.normalize(quantity.to_d - returned_quantity.to_d - lost_quantity.to_d)
  end

  private

  def settled_quantities_within_quantity
    if returned_quantity.to_d + lost_quantity.to_d > quantity.to_d
      errors.add(:base, :more_than_lent)
    end
  end

  def part_must_belong_to_same_organization
    if part.present? && loan.present? && part.organization_id != loan.organization_id
      errors.add(:part, :same_organization)
    end
  end

  def storage_location_must_belong_to_same_organization
    if storage_location.present? && loan.present? && storage_location.organization_id != loan.organization_id
      errors.add(:storage_location, :same_organization)
    end
  end
end

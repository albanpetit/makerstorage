class ProjectLine < ApplicationRecord
  # Associations
  belongs_to :project
  belongs_to :part, optional: true

  # Constants
  # How the line's part was resolved, surfaced in the review UI so the operator
  # can judge each proposed match. "none" = no inventory part found.
  MATCH_TYPES = %w[mpn sku name manual none].freeze

  # Validations
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :match_type, presence: true, inclusion: { in: MATCH_TYPES }
  validate :part_must_belong_to_same_organization

  # Methods - Availability
  def in_stock
    part&.total_quantity || 0
  end

  def shortfall
    return 0 if part.nil?
    [ quantity - in_stock, 0 ].max
  end

  # Matched to a real part AND enough of it is in stock to cover the requirement.
  def available?
    part.present? && shortfall.zero?
  end

  private

  def part_must_belong_to_same_organization
    if part.present? && part.organization_id != project&.organization_id
      errors.add(:part, "must belong to the same organization")
    end
  end
end

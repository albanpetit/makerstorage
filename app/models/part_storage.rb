class PartStorage < ApplicationRecord
  # Associations
  belongs_to :part
  belongs_to :storage_location

  # Validations
  validates :quantity, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :part_id, uniqueness: { scope: :storage_location_id }
  validate :storage_location_must_belong_to_same_organization

  # Scopes
  scope :with_stock, -> { where("quantity > 0") }
  scope :empty, -> { where(quantity: 0) }

  private

  def storage_location_must_belong_to_same_organization
    if part.present? && storage_location.present? && storage_location.organization_id != part.organization_id
      errors.add(:storage_location, "must belong to the same organization as the part")
    end
  end
end

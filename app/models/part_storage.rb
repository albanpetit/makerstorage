class PartStorage < ApplicationRecord
  # Associations
  belongs_to :part
  belongs_to :storage_location

  # In the part's unit (see Quantity).
  attribute :quantity, Quantity::Type.new

  # Validations
  validates :quantity, quantity: { greater_than_or_equal_to: 0, unit_of: :part }
  validates :part_id, uniqueness: { scope: :storage_location_id }
  validate :storage_location_must_belong_to_same_organization

  # Scopes
  scope :with_stock, -> { where("quantity > 0") }
  scope :empty, -> { where(quantity: 0) }

  private

  def storage_location_must_belong_to_same_organization
    if part.present? && storage_location.present? && storage_location.organization_id != part.organization_id
      errors.add(:storage_location, :same_organization_as_part)
    end
  end
end

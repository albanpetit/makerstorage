# One part in one zone of a stocktake: what the ledger expected there, and
# what was counted (nil until someone counts it).
class StocktakeLine < ApplicationRecord
  # Associations
  belongs_to :stocktake
  belongs_to :part
  belongs_to :storage_location
  belongs_to :counted_by, class_name: "User", optional: true
  # The adjustment the completed stocktake wrote for this line, if any.
  belongs_to :stock_movement, optional: true

  # Validations
  validates :expected_quantity, numericality: { only_integer: true, in: -MAX_INTEGER..MAX_INTEGER }
  validates :counted_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_INTEGER }, allow_nil: true
  validates :part_id, uniqueness: { scope: %i[stocktake_id storage_location_id] }
  validate :part_must_belong_to_the_organization
  validate :storage_location_must_be_counted, if: -> { new_record? || will_save_change_to_storage_location_id? }

  # Scopes
  scope :counted, -> { where.not(counted_quantity: nil) }
  scope :uncounted, -> { where(counted_quantity: nil) }

  # Methods
  def counted?
    !counted_quantity.nil?
  end

  # Counted minus expected: positive when more was found than the ledger
  # holds. Nil until counted.
  def difference
    counted_quantity - expected_quantity if counted?
  end

  # What the ledger holds for this part in this zone right now.
  def current_quantity
    PartStorage.where(part_id: part_id, storage_location_id: storage_location_id).pick(:quantity) || 0
  end

  private

  def part_must_belong_to_the_organization
    if part.present? && stocktake.present? && part.organization_id != stocktake.organization_id
      errors.add(:part, :same_organization)
    end
  end

  def storage_location_must_be_counted
    return if storage_location.nil? || stocktake.nil?

    if storage_location.organization_id != stocktake.organization_id || !stocktake.covers?(storage_location)
      errors.add(:storage_location, :not_in_stocktake)
    end
  end
end

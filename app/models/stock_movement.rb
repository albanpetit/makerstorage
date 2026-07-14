class StockMovement < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :part
  belongs_to :storage_location
  belongs_to :user, optional: true

  # Constants
  MOVEMENT_TYPES = %w[in out adjustment].freeze

  # Validations
  validates :movement_type, presence: true, inclusion: { in: MOVEMENT_TYPES }
  validates :quantity_delta, numericality: { only_integer: true, other_than: 0 }
  validate :quantity_delta_sign_matches_movement_type
  validate :storage_location_must_belong_to_same_organization
  validate :resulting_quantity_cannot_be_negative

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :of_type, ->(type) { where(movement_type: type) }
  scope :inbound, -> { where(movement_type: "in") }
  scope :outbound, -> { where(movement_type: "out") }
  scope :adjustments, -> { where(movement_type: "adjustment") }

  # Callbacks
  before_create :apply_to_part_storage

  # Methods
  def in?
    movement_type == "in"
  end

  def out?
    movement_type == "out"
  end

  def adjustment?
    movement_type == "adjustment"
  end

  private

  def quantity_delta_sign_matches_movement_type
    return if quantity_delta.nil?

    if movement_type == "in" && quantity_delta <= 0
      errors.add(:quantity_delta, "must be positive for an incoming movement")
    elsif movement_type == "out" && quantity_delta >= 0
      errors.add(:quantity_delta, "must be negative for an outgoing movement")
    end
  end

  def storage_location_must_belong_to_same_organization
    if storage_location.present? && storage_location.organization_id != organization_id
      errors.add(:storage_location, "must belong to the same organization")
    end
  end

  # Fast, friendly pre-check so `valid?` and the common overdraw case report the
  # error up front. This read is advisory only — apply_to_part_storage does the
  # authoritative, race-safe enforcement below.
  def resulting_quantity_cannot_be_negative
    return if quantity_delta.nil? || part.nil? || storage_location.nil? || organization&.allow_negative_stock

    current_quantity = PartStorage.find_by(part: part, storage_location: storage_location)&.quantity || 0
    if current_quantity + quantity_delta < 0
      errors.add(:quantity_delta, "would result in negative stock at this location")
    end
  end

  # Applies the delta to the PartStorage as a single atomic UPDATE, folding the
  # negative-stock guard into the statement's WHERE clause. Because the check and
  # the write are one statement, two concurrent "out" movements can't both read an
  # acceptable quantity and then both decrement past zero — whichever executes
  # second re-evaluates `quantity` and its guard matches no row. On overdraw the
  # update affects no rows, so we abort the create (rolling back the transaction).
  def apply_to_part_storage
    part_storage = PartStorage.find_or_create_by!(part: part, storage_location: storage_location) do |ps|
      ps.quantity = 0
    end

    scope = PartStorage.where(id: part_storage.id)
    scope = scope.where("quantity + ? >= 0", quantity_delta) unless organization&.allow_negative_stock

    if scope.update_all([ "quantity = quantity + ?", quantity_delta ]).zero?
      errors.add(:quantity_delta, "would result in negative stock at this location")
      throw(:abort)
    end
  end
end

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
  after_create :apply_to_part_storage

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

  def resulting_quantity_cannot_be_negative
    return if quantity_delta.nil? || part.nil? || storage_location.nil? || organization&.allow_negative_stock

    current_quantity = PartStorage.find_by(part: part, storage_location: storage_location)&.quantity || 0
    if current_quantity + quantity_delta < 0
      errors.add(:quantity_delta, "would result in negative stock at this location")
    end
  end

  def apply_to_part_storage
    part_storage = PartStorage.find_or_create_by!(part: part, storage_location: storage_location) do |ps|
      ps.quantity = 0
    end
    part_storage.increment!(:quantity, quantity_delta)
  end
end

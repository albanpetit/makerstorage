class StorageLocation < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :parent, class_name: "StorageLocation", optional: true
  has_many :children, class_name: "StorageLocation", foreign_key: :parent_id, dependent: :destroy

  has_many :part_storages, dependent: :destroy
  has_many :parts, through: :part_storages
  has_many :stock_movements, dependent: :restrict_with_error

  # Constants
  LOCATION_TYPES = %w[room cabinet shelf bench drawer box].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :location_type, presence: true, inclusion: { in: LOCATION_TYPES }
  validate :cannot_be_its_own_parent
  validate :parent_is_not_a_descendant
  validate :parent_must_belong_to_same_organization

  # Scopes
  scope :root_locations, -> { where(parent_id: nil) }
  scope :alphabetical, -> { order(:name) }
  scope :of_type, ->(type) { where(location_type: type) }

  # Methods
  def root?
    parent_id.nil?
  end

  def has_children?
    children.any?
  end

  def full_path
    path = [ name ]
    current = self
    while current.parent.present?
      current = current.parent
      path.unshift(current.name)
    end
    path.join(" > ")
  end

  def ancestors
    return [] if parent.nil?
    [ parent ] + parent.ancestors
  end

  def descendants
    children + children.flat_map(&:descendants)
  end

  def total_quantity
    part_storages.sum(:quantity)
  end

  private

  def cannot_be_its_own_parent
    if id.present? && parent_id == id
      errors.add(:parent_id, "cannot be itself")
    end
  end

  # Walk up the proposed parent's ancestry; reaching self means the new parent
  # is one of this zone's own descendants, which would create a cycle. The
  # visited guard keeps the check safe even against pre-existing bad data.
  def parent_is_not_a_descendant
    return if parent_id.blank? || id.blank?

    seen = []
    node = parent
    while node && seen.exclude?(node.id)
      if node.id == id
        errors.add(:parent_id, "cannot be moved under one of its own sub-zones")
        break
      end
      seen << node.id
      node = node.parent
    end
  end

  def parent_must_belong_to_same_organization
    if parent.present? && parent.organization_id != organization_id
      errors.add(:parent, "must belong to the same organization")
    end
  end
end

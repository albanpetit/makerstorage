class StorageLocation < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :parent, class_name: "StorageLocation", optional: true
  has_many :children, class_name: "StorageLocation", foreign_key: :parent_id, dependent: :destroy

  has_many :part_storages, dependent: :destroy
  has_many :parts, through: :part_storages
  has_many :stock_movements, dependent: :restrict_with_error
  # Purchase-order lines that will receive stock into this zone. Deleting the
  # zone would break their split (allocations must sum to the line quantity),
  # so it's blocked until the order is re-targeted.
  has_many :order_line_allocations, dependent: :restrict_with_error

  # Constants
  LOCATION_TYPES = %w[room cabinet shelf bench drawer box].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :location_type, presence: true, inclusion: { in: LOCATION_TYPES }
  # The scanner resolves a scanned label to a zone by code (case-insensitively),
  # so two zones sharing one would be ambiguous. Validation only, no unique
  # index: existing installs may already hold duplicates, which would fail the
  # migration; they get flagged the next time either zone is edited.
  validates :code, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validate :cannot_be_its_own_parent
  validate :parent_is_not_a_descendant
  validate :parent_must_belong_to_same_organization

  # Scopes
  scope :root_locations, -> { where(parent_id: nil) }
  scope :alphabetical, -> { order(:name) }
  scope :of_type, ->(type) { where(location_type: type) }

  # Methods

  # Loads a whole scope (e.g. one org's zones) into an id => StorageLocation map
  # with a single query, for passing to #full_path(cache:) so a serialization
  # loop resolves every zone's ancestry in memory instead of one query per level.
  def self.full_path_cache(scope = all)
    scope.select(:id, :name, :parent_id).index_by(&:id)
  end

  def root?
    parent_id.nil?
  end

  def has_children?
    children.any?
  end

  # Builds "Room > Cabinet > Shelf" by walking up to the root. In a serialization
  # loop this is an N+1 (one query per level, per location); pass `cache` — an
  # id => StorageLocation map of the sibling set (see .full_path_cache) — to
  # resolve parents in memory instead.
  def full_path(cache: nil)
    path = [ name ]
    current = self
    while (parent = cache ? cache[current.parent_id] : current.parent)
      current = parent
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

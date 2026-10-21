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
  # Box & bag numbering: the part whose IPN is this bag's code (see
  # #release_bag_occupant, which also clears that IPN when the bag goes away).
  has_one :bag_occupant, class_name: "Part", foreign_key: :bag_id, inverse_of: :bag, dependent: :nullify

  # Constants
  LOCATION_TYPES = %w[room cabinet shelf bench drawer box bag].freeze

  # Callbacks
  before_validation :number_bag, if: :bag?
  # Ahead of the dependent: :nullify above, while the occupant is still linked.
  before_destroy :release_bag_occupant, prepend: true, if: :bag?
  after_update :renumber_bags, if: -> { box? && saved_change_to_code? }
  after_update :sync_occupant_ipn, if: -> { bag? && saved_change_to_code? }

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :location_type, presence: true, inclusion: { in: LOCATION_TYPES }
  # The scanner resolves a scanned label to a zone by code (case-insensitively),
  # so two zones sharing one would be ambiguous. Validation only, no unique
  # index: existing installs may already hold duplicates, which would fail the
  # migration; they get flagged the next time either zone is edited.
  validates :code, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INTEGER }, allow_nil: true
  validate :bag_must_sit_in_a_coded_box, if: :bag?
  validate :box_with_bags_keeps_its_code, if: -> { box? && persisted? }
  validate :bag_codes_stay_unique, if: -> { box? && persisted? && code.present? && will_save_change_to_code? }
  validate :cannot_be_its_own_parent
  validate :parent_is_not_a_descendant
  validate :parent_must_belong_to_same_organization

  # Scopes
  scope :root_locations, -> { where(parent_id: nil) }
  scope :alphabetical, -> { order(:name) }
  scope :of_type, ->(type) { where(location_type: type) }
  scope :bags, -> { where(location_type: "bag") }

  # Methods

  # Loads a whole scope (e.g. one org's zones) into an id => StorageLocation map
  # with a single query, for passing to #full_path(cache:) so a serialization
  # loop resolves every zone's ancestry in memory instead of one query per level.
  def self.full_path_cache(scope = all)
    scope.select(:id, :name, :parent_id).index_by(&:id)
  end

  # A bag's code: its box's code and its number, joined with the org's IPN
  # separator ("A-3").
  def self.bag_code(box_code, position, separator)
    "#{box_code}#{separator}#{position}"
  end

  def bag?
    location_type == "bag"
  end

  def box?
    location_type == "box"
  end

  # Adds +count+ bags to this box, numbered after its last one.
  def add_bags!(count)
    raise ArgumentError, "only a box holds bags" unless box?

    transaction do
      Array.new(count) { organization.storage_locations.create!(parent: self, location_type: "bag") }
    end
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
    path_names(cache: cache).join(" > ")
  end

  # The zone names from the root down to this zone, e.g. ["Room", "Cabinet",
  # "Shelf"]. Takes the same +cache+ as #full_path.
  def path_names(cache: nil)
    path = [ name ]
    current = self
    while (parent = cache ? cache[current.parent_id] : current.parent)
      current = parent
      path.unshift(current.name)
    end
    path
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

  # Numbers a new bag after the last one in its box and derives its code (and,
  # when left blank, its name) from that number. The code always follows the
  # box, so it's recomputed on every save.
  def number_bag
    return unless parent&.box?

    self.position ||= (parent.children.bags.where.not(id: id).maximum(:position) || 0) + 1
    self.code = self.class.bag_code(parent.code, position, organization&.ipn_separator)
    self.name = "Bag #{code}" if name.blank?
  end

  def bag_must_sit_in_a_coded_box
    if parent.nil? || !parent.box?
      errors.add(:parent, :bag_parent_not_box)
    elsif parent.code.blank?
      errors.add(:parent, :bag_parent_without_code)
    end
  end

  def box_with_bags_keeps_its_code
    if code.blank? && children.bags.exists?
      errors.add(:code, :box_code_needed)
    end
  end

  # A renamed box recodes its bags (and their parts' IPNs) directly: refuse a
  # code that would give one of them a code or IPN already in use.
  def bag_codes_stay_unique
    renames = children.bags.includes(:bag_occupant).to_h { |bag| [ bag, self.class.bag_code(code, bag.position, organization.ipn_separator) ] }
    clashes = organization.bag_code_clashes(renames)
    errors.add(:code, :bag_codes_taken, codes: clashes.to_sentence) if clashes.any?
  end

  # A renamed box renames its bags (and so the IPNs of the parts in them).
  def renumber_bags
    children.bags.each(&:save!)
  end

  def sync_occupant_ipn
    bag_occupant&.update_column(:ipn, code)
  end

  def release_bag_occupant
    bag_occupant&.release_bag!
  end

  def cannot_be_its_own_parent
    if id.present? && parent_id == id
      errors.add(:parent_id, :own_parent)
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
        errors.add(:parent_id, :under_own_subzone)
        break
      end
      seen << node.id
      node = node.parent
    end
  end

  def parent_must_belong_to_same_organization
    if parent.present? && parent.organization_id != organization_id
      errors.add(:parent, :same_organization)
    end
  end
end

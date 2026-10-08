class Category < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :destroy
  has_many :parts, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :code, uniqueness: { scope: :organization_id, case_sensitive: false }, length: { maximum: 10 }, allow_blank: true
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }, allow_blank: true
  validate :cannot_be_its_own_parent
  validate :parent_cannot_be_a_descendant
  validate :parent_must_belong_to_same_organization

  # Scopes
  scope :root_categories, -> { where(parent_id: nil) }
  scope :subcategories, -> { where.not(parent_id: nil) }
  scope :alphabetical, -> { order(:name) }

  # Methods
  def root?
    parent_id.nil?
  end

  def has_children?
    children.any?
  end

  # Loads a whole scope (e.g. one org's categories) into an id => Category map
  # with a single query, for #full_path(cache:) — see StorageLocation's twin.
  def self.full_path_cache(scope = all)
    scope.select(:id, :name, :parent_id).index_by(&:id)
  end

  # "Passives > Resistors > SMD". In a serialization loop, pass +cache+ (see
  # .full_path_cache) so parents resolve in memory instead of one query per level.
  def full_path(cache: nil)
    path = [ name ]
    current = self
    seen = [ id ]
    while (parent = cache ? cache[current.parent_id] : current.parent) && seen.exclude?(parent.id)
      seen << parent.id
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

  # Ids of this category and its whole subtree — i.e. every category that would
  # disappear if this one were destroyed (children cascade-delete).
  def self_and_descendant_ids
    [ id ] + descendants.map(&:id)
  end

  private

  def cannot_be_its_own_parent
    if id.present? && parent_id == id
      errors.add(:parent_id, "cannot be itself")
    end
  end

  # Reassigning a category under one of its own descendants would create a
  # cycle, which would make full_path/ancestors/descendants loop forever. Walk
  # the proposed parent's chain via committed DB state (which is acyclic) rather
  # than the in-memory graph, which may already hold the pending cycle.
  def parent_cannot_be_a_descendant
    return if parent_id.nil? || id.nil? || parent_id == id

    ancestor_id = parent_id
    while ancestor_id
      if ancestor_id == id
        errors.add(:parent, "cannot be a descendant of this category")
        break
      end
      ancestor_id = self.class.where(id: ancestor_id).pick(:parent_id)
    end
  end

  def parent_must_belong_to_same_organization
    if parent.present? && parent.organization_id != organization_id
      errors.add(:parent, "must belong to the same organization")
    end
  end
end

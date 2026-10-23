class Category < ApplicationRecord
  # Activity log (Auditable).
  audited

  # Associations
  belongs_to :organization
  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :destroy
  has_many :parts, dependent: :restrict_with_error
  # Its parameter template (see #parameter_template_ids).
  has_many :category_parameters, -> { order(:position, :id) }, dependent: :destroy, autosave: true, inverse_of: :category
  has_many :parameter_definitions, through: :category_parameters

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :code, uniqueness: { scope: :organization_id, case_sensitive: false }, length: { maximum: 10 }, allow_blank: true
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }, allow_blank: true
  normalizes :kicad_symbol, with: ->(value) { value.strip.presence }
  validates :kicad_symbol, format: { with: KicadLibrary::REFERENCE_FORMAT, message: KicadLibrary::REFERENCE_MESSAGE },
    length: { maximum: 255 }, allow_blank: true
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
    path_names(cache: cache).join(" > ")
  end

  # ["Passives", "Resistors", "SMD"]: the names from the root down to this one.
  def path_names(cache: nil)
    path = [ name ]
    current = self
    seen = [ id ]
    while (parent = cache ? cache[current.parent_id] : current.parent) && seen.exclude?(parent.id)
      seen << parent.id
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

  # Ids of this category and its whole subtree — i.e. every category that would
  # disappear if this one were destroyed (children cascade-delete).
  def self_and_descendant_ids
    [ id ] + descendants.map(&:id)
  end

  # Sets the category's own template to the parameter ids given, in that
  # order. Saved with the category.
  def parameter_template=(ids)
    ids = Array(ids).map(&:to_i).uniq
    existing = category_parameters.index_by(&:parameter_definition_id)
    existing.each { |id, link| link.mark_for_destruction unless ids.include?(id) }
    ids.each_with_index do |id, index|
      link = existing[id] || category_parameters.build(parameter_definition_id: id)
      link.position = index
    end
  end

  # The parameters the part form proposes for this category: its ancestors'
  # template first (root down), then its own, each parameter once.
  def parameter_template_ids
    self.class.parameter_templates(organization)[id] || []
  end

  # category id => template parameter ids (inherited, as above) for every
  # category of +organization+, in two queries.
  def self.parameter_templates(organization)
    parents = organization.categories.pluck(:id, :parent_id).to_h
    own = CategoryParameter.joins(:category).where(categories: { organization_id: organization.id })
      .order(:position, :id).pluck(:category_id, :parameter_definition_id)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

    parents.keys.to_h do |category_id|
      chain = []
      current = category_id
      while current && chain.exclude?(current)
        chain.unshift(current)
        current = parents[current]
      end
      [ category_id, chain.flat_map { |id| own.fetch(id, []) }.uniq ]
    end
  end

  private

  def cannot_be_its_own_parent
    if id.present? && parent_id == id
      errors.add(:parent_id, :own_parent)
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
        errors.add(:parent, :descendant_parent)
        break
      end
      ancestor_id = self.class.where(id: ancestor_id).pick(:parent_id)
    end
  end

  def parent_must_belong_to_same_organization
    if parent.present? && parent.organization_id != organization_id
      errors.add(:parent, :same_organization)
    end
  end
end

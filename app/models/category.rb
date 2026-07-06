class Category < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :destroy
  has_many :parts, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :name, uniqueness: { scope: :organization_id }
  validates :code, uniqueness: { scope: :organization_id, case_sensitive: false }, length: { maximum: 10 }, allow_blank: true
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }, allow_blank: true
  validate :cannot_be_its_own_parent
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

  private

  def cannot_be_its_own_parent
    if id.present? && parent_id == id
      errors.add(:parent_id, "cannot be itself")
    end
  end

  def parent_must_belong_to_same_organization
    if parent.present? && parent.organization_id != organization_id
      errors.add(:parent, "must belong to the same organization")
    end
  end
end

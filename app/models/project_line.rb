class ProjectLine < ApplicationRecord
  # Associations
  belongs_to :project
  belongs_to :part, optional: true
  # Another project of the organization used as a sub-assembly, instead of a
  # part: +quantity+ units of it per kit (see ProjectStructure).
  belongs_to :subproject, class_name: "Project", optional: true, inverse_of: :used_in_lines

  # Constants
  # How the line's part was resolved, surfaced in the review UI so the operator
  # can judge each proposed match. "none" = no inventory part found,
  # "assembly" = the line uses another project (#subproject).
  MATCH_TYPES = %w[mpn sku supplier_sku value_footprint name manual assembly none].freeze

  # Validations
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INTEGER }
  validates :match_type, presence: true, inclusion: { in: MATCH_TYPES }
  validate :part_must_belong_to_same_organization
  validate :subproject_must_fit, if: :subproject

  def assembly?
    subproject_id.present?
  end

  # Methods - Availability
  def in_stock
    part&.total_quantity || 0
  end

  def shortfall
    return 0 if part.nil?
    [ quantity - in_stock, 0 ].max
  end

  # Matched to a real part AND enough of it is in stock to cover the requirement.
  def available?
    part.present? && shortfall.zero?
  end

  private

  # Same organization, not alongside a part, and no loop: a project can't use
  # itself or a project that (directly or not) uses it. The whole tree stays
  # within ProjectStructure::MAX_DEPTH levels.
  def subproject_must_fit
    if subproject.organization_id != project&.organization_id
      errors.add(:subproject, :same_organization)
    elsif part.present?
      errors.add(:subproject, :part_or_subproject)
    elsif project.persisted? && (subproject.id == project.id || ProjectStructure.descendant_ids(subproject.id).include?(project.id))
      errors.add(:subproject, :assembly_loop)
    elsif (subproject_id_changed? || new_record?) &&
          (project.persisted? ? ProjectStructure.depth_above(project.id) : 0) + 1 + ProjectStructure.depth_below(subproject.id) > ProjectStructure::MAX_DEPTH
      errors.add(:subproject, :assembly_too_deep, count: ProjectStructure::MAX_DEPTH)
    end
  end

  def part_must_belong_to_same_organization
    if part.present? && part.organization_id != project&.organization_id
      errors.add(:part, :same_organization)
    end
  end
end

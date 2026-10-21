# Two parts marked as "not duplicates" from the duplicates page, so
# PartDuplicates stops grouping them. One row per pair, the lower id in
# +part_id+ (see .dismiss!).
class PartDuplicateDismissal < ApplicationRecord
  belongs_to :part
  belongs_to :other_part, class_name: "Part"

  validates :other_part_id, uniqueness: { scope: :part_id }
  validate :parts_must_differ_and_share_organization

  # Records every pair among +parts+ (all of one organization) as dismissed.
  def self.dismiss!(parts)
    ids = parts.map(&:id).uniq.sort
    ids.combination(2).each { |a, b| find_or_create_by!(part_id: a, other_part_id: b) }
  end

  private

  def parts_must_differ_and_share_organization
    return unless part && other_part

    errors.add(:other_part, :another_part) if part_id >= other_part_id
    errors.add(:other_part, :same_organization) if part.organization_id != other_part.organization_id
  end
end

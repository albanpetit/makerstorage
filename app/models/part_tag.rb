class PartTag < ApplicationRecord
  belongs_to :part
  belongs_to :tag

  validates :part_id, uniqueness: { scope: :tag_id }
  validate :tag_must_belong_to_same_organization

  private

  def tag_must_belong_to_same_organization
    if tag.present? && part.present? && tag.organization_id != part.organization_id
      errors.add(:tag, "must belong to the same organization as the part")
    end
  end
end

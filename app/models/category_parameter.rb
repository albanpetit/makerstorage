# A parameter in a category's template: the part form proposes it for the
# category's parts and those of its sub-categories.
class CategoryParameter < ApplicationRecord
  belongs_to :category
  belongs_to :parameter_definition

  validates :parameter_definition_id, uniqueness: { scope: :category_id }
  validate :definition_must_belong_to_same_organization

  private

  def definition_must_belong_to_same_organization
    return if parameter_definition.nil? || category.nil?

    errors.add(:parameter_definition, "must belong to the same organization as the category") if parameter_definition.organization_id != category.organization_id
  end
end

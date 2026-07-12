# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create]

  # Inline creation from the part form so a fresh organization (which starts
  # with no categories) can define one without leaving the "New part" flow.
  def create
    category = current_organization.categories.build(category_params)

    if category.save
      redirect_back_or_to new_part_path, notice: "Category \"#{category.name}\" created."
    else
      redirect_back_or_to new_part_path, alert: "Failed to create category.", inertia: { errors: category.errors }
    end
  end

  private

  def category_params
    params.require(:category).permit(:name, :color, :parent_id)
  end
end

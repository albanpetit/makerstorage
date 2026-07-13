# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_category, only: %i[update destroy]

  def index
    categories = current_organization.categories
      .left_joins(:parts)
      .select("categories.*, COUNT(parts.id) AS parts_count")
      .group("categories.id")
      .alphabetical

    render inertia: "categories/index", props: {
      categories: categories.map { |category| serialize_category(category) }
    }
  end

  # Also used for inline creation from the part form so a fresh organization
  # (which starts with no categories) can define one without leaving the
  # "New part" flow. `redirect_back_or_to` returns to whichever page posted.
  def create
    category = current_organization.categories.build(category_params)

    if category.save
      redirect_back_or_to categories_path, notice: "Category \"#{category.name}\" created."
    else
      redirect_back_or_to categories_path, alert: "Failed to create category.", inertia: { errors: inertia_errors(category, as: :category) }
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "Category updated successfully."
    else
      redirect_back_or_to categories_path, alert: "Failed to update category.", inertia: { errors: inertia_errors(@category, as: :category) }
    end
  end

  def destroy
    affected_ids = @category.self_and_descendant_ids
    affected_parts = current_organization.parts.where(category_id: affected_ids)

    if affected_parts.exists?
      target = reassignment_target(affected_ids)
      unless target
        redirect_to categories_path,
          alert: "Select another category to move this category's parts to before deleting."
        return
      end

      moved = 0
      ActiveRecord::Base.transaction do
        moved = affected_parts.update_all(category_id: target.id, updated_at: Time.current)
        @category.destroy!
      end

      redirect_to categories_path,
        notice: "Category deleted. #{moved} part#{'s' unless moved == 1} moved to \"#{target.name}\"."
    elsif @category.destroy
      redirect_to categories_path, notice: "Category deleted successfully."
    else
      redirect_to categories_path, alert: @category.errors.full_messages.to_sentence
    end
  end

  private

  def set_category
    @category = current_organization.categories.find(params[:id])
  end

  # The category to move orphaned parts into. Must belong to the organization
  # and must not be one of the categories being deleted (self or a descendant).
  def reassignment_target(excluded_ids)
    target_id = params[:target_category_id]
    return nil if target_id.blank? || excluded_ids.include?(target_id.to_i)

    current_organization.categories.find_by(id: target_id)
  end

  def category_params
    params.require(:category).permit(:name, :code, :color, :description, :parent_id)
  end

  def serialize_category(category)
    {
      id: category.id,
      name: category.name,
      code: category.code,
      color: category.color,
      description: category.description,
      parent_id: category.parent_id,
      parts_count: category.attributes["parts_count"] || 0
    }
  end
end

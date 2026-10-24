# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Auth
  include OptionListSerializers

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_category, only: %i[update destroy]

  def index
    categories = current_organization.categories
      .preload(:category_parameters)
      .left_joins(:parts)
      .select("categories.*, COUNT(parts.id) AS parts_count")
      .group("categories.id")
      .alphabetical

    render inertia: "categories/index", props: {
      categories: categories.map { |category| serialize_category(category) },
      parameter_definitions: current_organization.parameter_definitions.alphabetical.map do |definition|
        { id: definition.id, name: definition.name, unit: definition.unit }
      end
    }
  end

  # Also used for inline creation from the part form's category picker, which
  # posts JSON so it works wherever the form is open (the part sidebar fetches
  # its option lists, so an Inertia reload wouldn't refresh them) and gets the
  # new category back to select it. HTML: `redirect_back_or_to` returns to
  # whichever page posted.
  def create
    category = current_organization.categories.build(category_params)
    saved = category.save

    respond_to do |format|
      format.json do
        if saved
          render json: { category: serialize_category_option(category) }, status: :created
        else
          render json: { errors: category.errors.to_hash(true).transform_values(&:first) }, status: :unprocessable_content
        end
      end
      format.html do
        if saved
          redirect_back_or_to categories_path, notice: t("flash.categories.category_created", category_name: category.name)
        else
          redirect_back_or_to categories_path, alert: t("flash.categories.failed_to_create_category"), inertia: { errors: inertia_errors(category, as: :category) }
        end
      end
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: t("flash.categories.category_updated_successfully")
    else
      redirect_back_or_to categories_path, alert: t("flash.categories.failed_to_update_category"), inertia: { errors: inertia_errors(@category, as: :category) }
    end
  end

  def destroy
    affected_ids = @category.self_and_descendant_ids
    affected_parts = current_organization.parts.where(category_id: affected_ids)

    if affected_parts.exists?
      target = reassignment_target(affected_ids)
      unless target
        redirect_to categories_path,
          alert: t("flash.categories.select_another_category_to_move_this")
        return
      end

      moved = 0
      ActiveRecord::Base.transaction do
        moved = affected_parts.update_all(category_id: target.id, updated_at: Time.current)
        ActivityEvent.record!(current_organization, "update", details: { "updated" => moved, "category" => target.name })
        @category.destroy!
      end

      redirect_to categories_path,
        notice: t("flash.categories.deleted_and_moved", count: moved, category: target.name)
    elsif @category.destroy
      redirect_to categories_path, notice: t("flash.categories.category_deleted_successfully")
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
    permitted = params.require(:category).permit(:name, :code, :color, :description, :parent_id, :kicad_symbol, parameter_definition_ids: [])
    # Through-association ids are looked up across every organization: keep
    # this one's parameters, in the order given (the template's order).
    if permitted.key?(:parameter_definition_ids)
      ids = Array(permitted.delete(:parameter_definition_ids)).compact_blank.map(&:to_i).uniq
      owned = current_organization.parameter_definitions.where(id: ids).pluck(:id).to_set
      permitted[:parameter_template] = ids.select { |id| owned.include?(id) }
    end
    permitted
  end

  def serialize_category(category)
    {
      id: category.id,
      name: category.name,
      code: category.code,
      color: category.color,
      description: category.description,
      parent_id: category.parent_id,
      kicad_symbol: category.kicad_symbol,
      parameter_definition_ids: category.category_parameters.map(&:parameter_definition_id),
      parts_count: category.attributes["parts_count"] || 0
    }
  end
end

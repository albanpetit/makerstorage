# frozen_string_literal: true

# The organization's technical parameters (Resistance, Tolerance…): the
# Parameters page, and the JSON list the part form loads to propose them.
class ParameterDefinitionsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy standard]
  before_action :set_definition, only: %i[update destroy]

  def index
    respond_to do |format|
      # The part form: every parameter, and each category's template
      # (inherited from its parents).
      format.json do
        render json: {
          definitions: current_organization.parameter_definitions.alphabetical.map { |definition| serialize_option(definition) },
          templates: Category.parameter_templates(current_organization)
        }
      end
      format.html do
        definitions = current_organization.parameter_definitions.alphabetical
          .preload(:categories)
          .left_joins(:part_parameters)
          .select("parameter_definitions.*, COUNT(part_parameters.id) AS parts_count")
          .group("parameter_definitions.id")
        standard_names = ParameterDefinition::STANDARD.map { |standard| standard[:name].downcase }

        render inertia: "parameter_definitions/index", props: {
          definitions: definitions.map { |definition| serialize_definition(definition) },
          standard_missing: (standard_names - definitions.map { |definition| definition.name.downcase }).size
        }
      end
    end
  end

  # JSON for inline creation from the part form, like categories.
  def create
    definition = current_organization.parameter_definitions.build(definition_params)
    saved = definition.save

    respond_to do |format|
      format.json do
        if saved
          render json: { definition: serialize_option(definition) }, status: :created
        else
          render json: { errors: definition.errors.to_hash(true).transform_values(&:first) }, status: :unprocessable_content
        end
      end
      format.html do
        if saved
          redirect_to parameter_definitions_path, notice: t("flash.parameter_definitions.created", name: definition.name)
        else
          redirect_back_or_to parameter_definitions_path, inertia: { errors: inertia_errors(definition, as: :parameter_definition) }
        end
      end
    end
  end

  def update
    if @definition.update(definition_params)
      redirect_to parameter_definitions_path, notice: t("flash.parameter_definitions.updated")
    else
      redirect_back_or_to parameter_definitions_path, inertia: { errors: inertia_errors(@definition, as: :parameter_definition) }
    end
  end

  def destroy
    count = @definition.part_parameters.count
    @definition.destroy!
    redirect_to parameter_definitions_path,
      notice: count.positive? ? t("flash.parameter_definitions.deleted_with_values", name: @definition.name, count: count) : t("flash.parameter_definitions.deleted", name: @definition.name)
  end

  # Adds the standard parameters, their category templates, and the values
  # the parts' existing fields provide.
  def standard
    result = ParameterDefinition.install_standard!(current_organization)
    redirect_to parameter_definitions_path,
      notice: t("flash.parameter_definitions.standard_installed",
                added: t("flash.parameter_definitions.parameters_added", count: result[:added]),
                categories: t("flash.parameter_definitions.categories_templated", count: result[:categories]),
                values: t("flash.parameter_definitions.values_filled", count: result[:parameters]))
  rescue ActiveRecord::RecordInvalid => e
    redirect_to parameter_definitions_path, alert: t("flash.parameter_definitions.standard_failed", errors: e.record.errors.full_messages.to_sentence)
  end

  private

  def set_definition
    @definition = current_organization.parameter_definitions.find(params[:id])
  end

  def definition_params
    params.require(:parameter_definition).permit(:name, :value_type, :unit, :description)
  end

  def serialize_option(definition)
    { id: definition.id, name: definition.name, value_type: definition.value_type, unit: definition.unit }
  end

  def serialize_definition(definition)
    serialize_option(definition).merge(
      description: definition.description,
      parts_count: definition.attributes["parts_count"] || 0,
      category_names: definition.categories.map(&:name).sort_by(&:downcase)
    )
  end
end

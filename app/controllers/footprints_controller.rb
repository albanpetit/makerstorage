# frozen_string_literal: true

class FootprintsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_footprint, only: %i[update destroy]

  def index
    footprints = current_organization.footprints
      .left_joins(:parts)
      .select("footprints.*, COUNT(parts.id) AS parts_count")
      .group("footprints.id")
      .alphabetical

    render inertia: "footprints/index", props: {
      footprints: footprints.map { |footprint| serialize_footprint(footprint) },
      mounting_types: Footprint::MOUNTING_TYPES
    }
  end

  def create
    footprint = current_organization.footprints.build(footprint_params)

    if footprint.save
      redirect_to footprints_path, notice: "Footprint created successfully."
    else
      redirect_back_or_to footprints_path, alert: "Failed to create footprint.", inertia: { errors: footprint.errors }
    end
  end

  def update
    if @footprint.update(footprint_params)
      redirect_to footprints_path, notice: "Footprint updated successfully."
    else
      redirect_back_or_to footprints_path, alert: "Failed to update footprint.", inertia: { errors: @footprint.errors }
    end
  end

  def destroy
    if @footprint.destroy
      redirect_to footprints_path, notice: "Footprint deleted successfully."
    else
      redirect_to footprints_path, alert: @footprint.errors.full_messages.to_sentence
    end
  end

  private

  def set_footprint
    @footprint = current_organization.footprints.find(params[:id])
  end

  def footprint_params
    params.require(:footprint).permit(:name, :description, :mounting_type)
  end

  def serialize_footprint(footprint)
    {
      id: footprint.id,
      name: footprint.name,
      description: footprint.description,
      mounting_type: footprint.mounting_type,
      parts_count: footprint.attributes["parts_count"] || 0
    }
  end
end

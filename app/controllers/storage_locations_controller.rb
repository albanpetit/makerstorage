# frozen_string_literal: true

class StorageLocationsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy]
  before_action :set_storage_location, only: %i[update destroy]

  def index
    locations = current_organization.storage_locations.alphabetical

    render inertia: "storage_locations/index", props: {
      storage_locations: locations.map { |location| serialize_location(location) },
      part_storages: serialize_part_storages,
      recent_movements: serialize_recent_movements
    }
  end

  def create
    location = current_organization.storage_locations.build(storage_location_params)

    if location.save
      redirect_to storage_locations_path, notice: "Storage zone created successfully."
    else
      redirect_to storage_locations_path, alert: location.errors.full_messages.to_sentence, inertia: { errors: inertia_errors(location, as: :storage_location) }
    end
  end

  def update
    if @storage_location.update(storage_location_params)
      redirect_to storage_locations_path, notice: "Storage zone updated successfully."
    else
      redirect_to storage_locations_path, alert: @storage_location.errors.full_messages.to_sentence, inertia: { errors: inertia_errors(@storage_location, as: :storage_location) }
    end
  end

  def destroy
    if @storage_location.has_children?
      redirect_to storage_locations_path, alert: "Cannot delete a zone that contains sub-zones."
      return
    end

    if @storage_location.destroy
      redirect_to storage_locations_path, notice: "Storage zone deleted successfully."
    else
      redirect_to storage_locations_path, alert: @storage_location.errors.full_messages.to_sentence
    end
  end

  private

  def set_storage_location
    @storage_location = current_organization.storage_locations.find(params[:id])
  end

  def storage_location_params
    params.require(:storage_location).permit(:name, :location_type, :code, :parent_id)
  end

  def serialize_location(location)
    {
      id: location.id,
      name: location.name,
      location_type: location.location_type,
      code: location.code,
      parent_id: location.parent_id
    }
  end

  def serialize_part_storages
    current_organization.storage_locations.includes(part_storages: :part).flat_map(&:part_storages).map do |part_storage|
      part = part_storage.part
      {
        location_id: part_storage.storage_location_id,
        quantity: part_storage.quantity,
        part: {
          id: part.id,
          reference: part.mpn.presence || part.sku.presence || part.name,
          name: part.name,
          package_type: part.package_type
        }
      }
    end
  end

  def serialize_recent_movements
    current_organization.stock_movements
      .includes(:part)
      .recent
      .limit(150)
      .map do |movement|
        {
          location_id: movement.storage_location_id,
          part_reference: movement.part.mpn.presence || movement.part.sku.presence || movement.part.name,
          movement_type: movement.movement_type,
          quantity_delta: movement.quantity_delta,
          reason: movement.reason,
          created_at: movement.created_at.iso8601
        }
      end
  end
end

# frozen_string_literal: true

class StorageLocationsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy move_stock add_bags]
  before_action :set_storage_location, only: %i[update destroy add_bags]

  MAX_BAGS_PER_REQUEST = 200

  def index
    locations = current_organization.storage_locations.alphabetical

    render inertia: "storage_locations/index", props: {
      storage_locations: locations.map { |location| serialize_location(location) },
      part_storages: serialize_part_storages,
      recent_movements: serialize_recent_movements,
      # Joins a box code and bag number into the bag's code (box & bag storage).
      bag_separator: current_organization.ipn_separator,
      # `?zone=ID` (the "Open zone" link of a scanned label) opens that zone.
      selected_zone_id: current_organization.storage_locations.find_by(id: params[:zone])&.id
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

  # Box & bag storage: appends +count+ numbered bags to a box (A-1, A-2, …).
  def add_bags
    count = params[:count].to_i
    unless @storage_location.box?
      return redirect_to storage_locations_path(zone: @storage_location.id), alert: "Only a box can hold bags."
    end
    unless count.between?(1, MAX_BAGS_PER_REQUEST)
      return redirect_to storage_locations_path(zone: @storage_location.id), alert: "Add between 1 and #{MAX_BAGS_PER_REQUEST} bags at a time."
    end

    bags = @storage_location.add_bags!(count)
    redirect_to storage_locations_path(zone: @storage_location.id),
      notice: "Added #{count} #{'bag'.pluralize(count)} (#{[ bags.first.code, bags.last.code ].uniq.join(' to ')})."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to storage_locations_path(zone: @storage_location.id), alert: e.record.errors.full_messages.to_sentence
  end

  # Relocates part stock from one zone to another. Each move is recorded through
  # the ledger as an `out` at the source plus an `in` at the destination, so the
  # audit trail and overdraw guards stay intact. The whole batch is atomic: if any
  # single move is invalid (unknown part, non-positive amount, or more than what's
  # on hand) the transaction rolls back and nothing moves.
  def move_stock
    from = current_organization.storage_locations.find_by(id: params[:from_location_id])
    to = current_organization.storage_locations.find_by(id: params[:to_location_id])

    if from.nil? || to.nil?
      return redirect_back_or_to(storage_locations_path, alert: "Unknown storage zone.")
    end
    if from.id == to.id
      return redirect_back_or_to(storage_locations_path, alert: "Pick a different destination zone.")
    end

    moves = Array(params[:moves]).filter_map do |raw|
      part = current_organization.parts.find_by(id: raw[:part_id])
      next if part.nil?

      { part: part, quantity: raw[:quantity].to_i }
    end

    if moves.empty?
      return redirect_back_or_to(storage_locations_path, alert: "No components selected to move.")
    end

    error = nil
    ActiveRecord::Base.transaction do
      moves.each do |move|
        available = PartStorage.find_by(part: move[:part], storage_location: from)&.quantity || 0
        if move[:quantity] <= 0 || move[:quantity] > available
          error = "#{move[:part].reference}: can't move #{move[:quantity]} (only #{available} in #{from.name})."
          raise ActiveRecord::Rollback
        end

        outgoing = current_organization.stock_movements.build(
          part: move[:part], storage_location: from, movement_type: "out",
          quantity_delta: -move[:quantity], reason: "Moved to #{to.name}", user: current_user
        )
        incoming = current_organization.stock_movements.build(
          part: move[:part], storage_location: to, movement_type: "in",
          quantity_delta: move[:quantity], reason: "Moved from #{from.name}", user: current_user
        )

        unless outgoing.save && incoming.save
          error = (outgoing.errors.full_messages + incoming.errors.full_messages).to_sentence.presence ||
                  "Could not move #{move[:part].reference}."
          raise ActiveRecord::Rollback
        end
      end
    end

    if error
      redirect_back_or_to(storage_locations_path, alert: error)
    else
      count = moves.size
      redirect_back_or_to(storage_locations_path, notice: "Moved #{count} component#{'s' unless count == 1} to #{to.name}.")
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
      parent_id: location.parent_id,
      position: location.position
    }
  end

  # An emptied row stays listed under its zone, except in a bag another part
  # holds: that one was stray stock moved out, and the bag holds one component.
  def serialize_part_storages
    bag_holders = current_organization.parts.where.not(bag_id: nil).pluck(:bag_id, :id).to_h
    part_storages = current_organization.storage_locations.includes(part_storages: :part).flat_map(&:part_storages)
    part_storages.reject! do |part_storage|
      holder = bag_holders[part_storage.storage_location_id]
      part_storage.quantity.zero? && holder && holder != part_storage.part_id
    end
    part_storages.map do |part_storage|
      part = part_storage.part
      {
        location_id: part_storage.storage_location_id,
        quantity: part_storage.quantity,
        part: {
          id: part.id,
          reference: part.reference,
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
          part_reference: movement.part.reference,
          movement_type: movement.movement_type,
          quantity_delta: movement.quantity_delta,
          reason: movement.reason,
          created_at: movement.created_at.iso8601
        }
      end
  end
end

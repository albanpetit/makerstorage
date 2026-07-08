# frozen_string_literal: true

class StockMovementsController < ApplicationController
  include Auth

  before_action :verify_organization_access

  def index
    movements = current_organization.stock_movements
      .includes(:storage_location, :user, part: :category)
      .order(:created_at)
      .to_a

    running_balances = compute_running_balances(movements)

    render inertia: "stock_movements/index", props: {
      movements: movements.reverse.map { |movement| serialize_movement(movement, running_balances[movement.id]) },
      parts: serialize_parts,
      storage_locations: serialize_storage_locations
    }
  end

  def create
    movement = current_organization.stock_movements.build(movement_params)
    movement.user = current_user
    movement.quantity_delta = signed_quantity

    if movement.save
      redirect_back_or_to stock_movements_path, notice: "Movement recorded successfully."
    else
      redirect_back_or_to stock_movements_path, alert: "Failed to record movement.", inertia: { errors: movement.errors }
    end
  end

  private

  def movement_params
    params.require(:stock_movement).permit(:part_id, :storage_location_id, :movement_type, :reason)
  end

  def signed_quantity
    magnitude = params.dig(:stock_movement, :quantity).to_i

    case params.dig(:stock_movement, :movement_type)
    when "out"
      -magnitude
    when "adjustment"
      params.dig(:stock_movement, :direction) == "decrease" ? -magnitude : magnitude
    else
      magnitude
    end
  end

  # For each (part, location) pair, movements are chronologically ordered and
  # summed so every movement can show the resulting stock level at that point
  # in time, without persisting a snapshot column.
  def compute_running_balances(movements)
    balances = Hash.new(0)
    movements.each_with_object({}) do |movement, result|
      key = [ movement.part_id, movement.storage_location_id ]
      balances[key] += movement.quantity_delta
      result[movement.id] = balances[key]
    end
  end

  def serialize_movement(movement, balance_after)
    part = movement.part
    {
      id: movement.id,
      created_at: movement.created_at.iso8601,
      movement_type: movement.movement_type,
      quantity_delta: movement.quantity_delta,
      reason: movement.reason,
      balance_after: balance_after,
      user_name: movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil,
      location_name: movement.storage_location.name,
      part: {
        id: part.id,
        reference: part.mpn.presence || part.sku.presence || part.name,
        name: part.name,
        category: part.category ? { name: part.category.name, color: part.category.color } : nil
      }
    }
  end

  def serialize_parts
    current_organization.parts.alphabetical.map do |part|
      { id: part.id, reference: part.mpn.presence || part.sku.presence || part.name, name: part.name }
    end
  end

  def serialize_storage_locations
    current_organization.storage_locations.alphabetical.map do |location|
      { id: location.id, name: location.full_path }
    end
  end
end

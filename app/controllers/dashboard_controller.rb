# frozen_string_literal: true

class DashboardController < ApplicationController
  include Auth

  before_action :verify_organization_access

  def index
    render inertia: "dashboard/index", props: {
      stats: {
        references_count: current_organization.total_parts_count,
        total_units: current_organization.total_stock_units,
        stock_value: current_organization.total_stock_value.to_f,
        alerts_count: current_organization.low_stock_parts_count,
        currency: current_organization.currency
      },
      category_breakdown: current_organization.category_breakdown,
      low_stock_parts: serialize_low_stock_parts,
      recent_movements: serialize_recent_movements
    }
  end

  private

  def serialize_low_stock_parts
    current_organization.parts.low_stock.includes(:storage_locations)
      .sort_by { |part| part.total_quantity.to_f / part.min_stock_threshold }
      .first(6)
      .map do |part|
        {
          id: part.id,
          reference: part.mpn.presence || part.sku.presence || part.name,
          name: part.name,
          location_name: part.storage_locations.first&.name,
          quantity: part.total_quantity,
          min_stock_threshold: part.min_stock_threshold
        }
      end
  end

  def serialize_recent_movements
    current_organization.stock_movements
      .includes(:part, :storage_location, :user)
      .recent
      .limit(10)
      .map do |movement|
        {
          id: movement.id,
          part_name: movement.part.name,
          location_name: movement.storage_location.name,
          movement_type: movement.movement_type,
          quantity_delta: movement.quantity_delta,
          reason: movement.reason,
          user_name: movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil,
          created_at: movement.created_at.iso8601
        }
      end
  end
end

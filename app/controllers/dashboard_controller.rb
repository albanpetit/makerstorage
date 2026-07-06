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
      recent_movements: serialize_recent_movements
    }
  end

  private

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

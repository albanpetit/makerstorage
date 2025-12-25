# frozen_string_literal: true

class PartsController < ApplicationController
  include Auth

  def index
    parts = current_organization.parts
      .includes(:category, :footprint)
      .alphabetical

    render inertia: "parts/index", props: {
      parts: parts.map { |part| serialize_part(part) }
    }
  end

  private

  def current_organization
    # For now, get the first organization of the current user
    # Later this should be based on session/selected organization
    current_user.organizations.first
  end

  def serialize_part(part)
    {
      id: part.id,
      name: part.name,
      mpn: part.mpn,
      sku: part.sku,
      manufacturer: part.manufacturer,
      value: part.value,
      status: part.status,
      # total_quantity: part.total_quantity,
      min_stock_threshold: part.min_stock_threshold,
      unit_price: part.unit_price,
      category: part.category ? { id: part.category.id, name: part.category.name } : nil,
      footprint: part.footprint ? { id: part.footprint.id, name: part.footprint.name } : nil
    }
  end
end

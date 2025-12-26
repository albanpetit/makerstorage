# frozen_string_literal: true

class PartsController < ApplicationController
  include Auth

  before_action :verify_organization_access

  def index
    parts = current_organization.parts
      .includes(:category, :footprint)
      .alphabetical

    render inertia: "parts/index", props: {
      parts: parts.map { |part| serialize_part(part) }
    }
  end

  def new
    render inertia: "parts/new", props: {
      categories: serialize_categories,
      footprints: serialize_footprints,
      suppliers: serialize_suppliers
    }
  end

  def create
    part = current_organization.parts.build(part_params)

    if part.save
      redirect_to parts_path, notice: "Part created successfully."
    else
      redirect_to new_part_path, alert: "Failed to create part.", inertia: { errors: part.errors }
    end
  end

  private

  def part_params
    params.require(:part).permit(
      :name, :mpn, :sku, :barcode, :manufacturer, :description,
      :value, :tolerance, :voltage_rating, :power_rating, :package_type,
      :category_id, :footprint_id, :preferred_supplier_id, :supplier_sku,
      :unit_price, :min_stock_threshold, :target_stock, :lead_time_days,
      :status, :rohs_compliant, :storage_notes
    )
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

  def serialize_categories
    current_organization.categories.alphabetical.map do |category|
      { id: category.id, name: category.full_path }
    end
  end

  def serialize_footprints
    current_organization.footprints.alphabetical.map do |footprint|
      { id: footprint.id, name: footprint.name, mounting_type: footprint.mounting_type }
    end
  end

  def serialize_suppliers
    current_organization.suppliers.order(:name).map do |supplier|
      { id: supplier.id, name: supplier.name }
    end
  end
end

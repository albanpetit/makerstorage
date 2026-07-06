# frozen_string_literal: true

class PartsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :set_part, only: %i[show edit update destroy]

  def index
    parts = current_organization.parts
      .includes(:category, :footprint, :part_storages)
      .alphabetical

    render inertia: "parts/index", props: {
      parts: parts.map { |part| serialize_part(part) }
    }
  end

  def show
    render inertia: "parts/show", props: {
      part: serialize_part_full(@part)
    }
  end

  def new
    render inertia: "parts/new", props: {
      categories: serialize_categories,
      footprints: serialize_footprints,
      suppliers: serialize_suppliers
    }
  end

  def edit
    render inertia: "parts/edit", props: {
      part: serialize_part_full(@part),
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

  def update
    if @part.update(part_params)
      redirect_to edit_part_path(@part), notice: "Part updated successfully."
    else
      redirect_to edit_part_path(@part), alert: "Failed to update part.", inertia: { errors: @part.errors }
    end
  end

  def destroy
    @part.destroy
    redirect_to parts_path, notice: "Part deleted successfully."
  end

  private

  def set_part
    @part = current_organization.parts.find(params[:id])
  end

  def part_params
    params.require(:part).permit(
      :name, :mpn, :sku, :barcode, :manufacturer, :description,
      :value, :tolerance, :voltage_rating, :power_rating, :package_type,
      :category_id, :footprint_id,
      :unit_price, :min_stock_threshold, :target_stock,
      :status, :rohs_compliant, :storage_notes,
      part_suppliers_attributes: [
        :id, :supplier_id, :supplier_sku, :unit_price, :lead_time_days,
        :url, :is_preferred, :notes, :_destroy
      ]
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
      total_quantity: part.total_quantity,
      min_stock_threshold: part.min_stock_threshold,
      unit_price: part.unit_price,
      category: part.category ? { id: part.category.id, name: part.category.name } : nil,
      footprint: part.footprint ? { id: part.footprint.id, name: part.footprint.name } : nil
    }
  end

  def serialize_part_full(part)
    serialize_part(part).merge(
      barcode: part.barcode,
      description: part.description,
      tolerance: part.tolerance,
      voltage_rating: part.voltage_rating,
      power_rating: part.power_rating,
      package_type: part.package_type,
      target_stock: part.target_stock,
      lead_time_days: part.lead_time_days,
      rohs_compliant: part.rohs_compliant,
      storage_notes: part.storage_notes,
      category_id: part.category_id,
      footprint_id: part.footprint_id,
      part_suppliers: part.part_suppliers.includes(:supplier).map { |ps| serialize_part_supplier(ps) }
    )
  end

  def serialize_part_supplier(ps)
    {
      id: ps.id,
      supplier_id: ps.supplier_id,
      supplier_name: ps.supplier.name,
      supplier_sku: ps.supplier_sku,
      unit_price: ps.unit_price,
      lead_time_days: ps.lead_time_days,
      url: ps.url,
      is_preferred: ps.is_preferred,
      notes: ps.notes
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

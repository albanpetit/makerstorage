# frozen_string_literal: true

require "csv"

class PartsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :set_part, only: %i[show edit update destroy]

  def index
    parts = current_organization.parts
      .includes(:category, :footprint, :part_storages, :storage_locations, part_suppliers: :supplier)
      .alphabetical

    render inertia: "parts/index", props: {
      parts: parts.map { |part| serialize_part(part) },
      initial_query: params[:search].to_s,
      categories: serialize_categories,
      storage_locations: serialize_storage_locations
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
      assign_initial_stock(part)
      redirect_to parts_path, notice: "Part created successfully."
    else
      redirect_back_or_to new_part_path, alert: "Failed to create part.", inertia: { errors: part.errors }
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

  # Column names accepted per logical field, checked in order (French/English/
  # common BOM export synonyms). CSV::foreach with header_converters: :symbol
  # downcases, underscores whitespace, and strips accented characters, so
  # "Unit Price" -> :unit_price and "Désignation"/"Quantité" -> :dsignation/:quantit.
  IMPORT_COLUMN_SYNONYMS = {
    name: %i[name designation dsignation],
    category: %i[category categorie catgorie],
    mpn: %i[mpn],
    sku: %i[sku reference ref rfrence],
    manufacturer: %i[manufacturer],
    value: %i[value valeur],
    package: %i[package boitier botier],
    location: %i[location emplacement],
    supplier: %i[supplier fournisseur],
    quantity: %i[quantity quantite quantit qty],
    min_stock_threshold: %i[min_stock_threshold seuil min],
    unit_price: %i[unit_price pu pu_eur price],
    status: %i[status statut]
  }.freeze

  def import
    file = params[:file]
    return redirect_to(parts_path, alert: "Please choose a CSV file to import.") unless file

    created = 0
    updated = 0
    skipped = 0
    separator = File.foreach(file.path).first.to_s.include?(";") ? ";" : ","

    begin
      CSV.foreach(file.path, headers: true, header_converters: :symbol, col_sep: separator) do |row|
        name = import_value(row, :name)
        category_name = import_value(row, :category)

        if name.blank? || category_name.blank?
          skipped += 1
          next
        end

        category = current_organization.categories.find_or_create_by!(name: category_name)
        part = find_existing_part(row)
        is_new = part.nil?
        part ||= current_organization.parts.build

        part.assign_attributes(
          name: name,
          category: category,
          mpn: import_value(row, :mpn),
          sku: import_value(row, :sku),
          manufacturer: import_value(row, :manufacturer),
          value: import_value(row, :value),
          package_type: import_value(row, :package),
          unit_price: import_value(row, :unit_price)&.tr(",", "."),
          min_stock_threshold: import_value(row, :min_stock_threshold) || 0,
          status: import_value(row, :status) || "active"
        )

        if part.save
          is_new ? created += 1 : updated += 1
          assign_stock(part, row)
        else
          skipped += 1
        end
      end
    rescue CSV::MalformedCSVError
      return redirect_to(parts_path, alert: "Could not parse that file as CSV.")
    end

    redirect_to parts_path, notice: "Import complete: #{created} created, #{updated} updated, #{skipped} skipped."
  end

  private

  # Returns the first present value among the synonym columns for +field+.
  def import_value(row, field)
    IMPORT_COLUMN_SYNONYMS.fetch(field).each do |key|
      value = row[key].to_s.strip
      return value if value.present?
    end
    nil
  end

  def assign_stock(part, row)
    location_name = import_value(row, :location)
    return if location_name.blank?

    location = current_organization.storage_locations.find_or_create_by!(name: location_name) do |loc|
      loc.location_type = "shelf"
    end
    quantity = import_value(row, :quantity).to_i
    PartStorage.find_or_initialize_by(part: part, storage_location: location).update!(quantity: quantity)
  end

  def find_existing_part(row)
    mpn = import_value(row, :mpn)
    sku = import_value(row, :sku)

    if mpn.present?
      current_organization.parts.find_by(mpn: mpn)
    elsif sku.present?
      current_organization.parts.find_by(sku: sku)
    end
  end

  def assign_initial_stock(part)
    quantity = params[:initial_quantity].to_i
    return if params[:initial_location_id].blank? || quantity <= 0

    location = current_organization.storage_locations.find_by(id: params[:initial_location_id])
    return unless location

    StockMovement.create!(
      organization: current_organization,
      part: part,
      storage_location: location,
      user: current_user,
      movement_type: "in",
      quantity_delta: quantity,
      reason: "Initial stock"
    )
  end

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
      package_type: part.package_type,
      status: part.status,
      total_quantity: part.total_quantity,
      min_stock_threshold: part.min_stock_threshold,
      unit_price: part.unit_price&.to_f,
      location_names: part.storage_locations.map(&:name),
      supplier_name: part.preferred_supplier&.name,
      category: part.category ? { id: part.category.id, name: part.category.name, color: part.category.color } : nil,
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
      unit_price: ps.unit_price&.to_f,
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

  def serialize_storage_locations
    current_organization.storage_locations.alphabetical.map do |location|
      { id: location.id, name: location.full_path }
    end
  end
end

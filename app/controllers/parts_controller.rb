# frozen_string_literal: true

require "csv"

class PartsController < ApplicationController
  include Auth
  include OptionListSerializers

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update destroy import lookup bulk_stock bulk_move bulk_destroy]
  before_action :set_part, only: %i[show edit update destroy]

  def index
    parts = current_organization.parts
      .includes(:category, :footprint, :part_storages, :storage_locations, part_suppliers: :supplier)
      .with_attached_images
      .alphabetical

    render inertia: "parts/index", props: {
      parts: parts.map { |part| serialize_part(part) },
      initial_query: params[:search].to_s,
      categories: serialize_categories,
      footprints: serialize_footprints,
      suppliers: serialize_suppliers,
      tags: serialize_tags,
      storage_locations: serialize_storage_locations,
      supplier_lookup_enabled: current_organization.supplier_lookup_configured?,
      ipn_manual_entry: current_organization.ipn_generation_mode == "manual",
      open_add: params[:new].present?
    }
  end

  def show
    # The part detail lives in the sidebar (opened from the inventory list and
    # other pages), which fetches this action as JSON. The payload carries both
    # the part detail and the option lists its embedded edit modal needs.
    respond_to do |format|
      format.json do
        movements = @part.stock_movements
          .includes(:storage_location, :user)
          .order(created_at: :desc)
          .limit(10)

        render json: {
          part: serialize_part_full(@part),
          storages: @part.part_storages.includes(:storage_location).map { |ps| serialize_part_storage(ps) },
          movements: movements.map { |movement| serialize_part_movement(movement) },
          storage_locations: serialize_storage_locations,
          categories: serialize_categories,
          footprints: serialize_footprints,
          suppliers: serialize_suppliers,
          tags: serialize_tags,
          supplier_lookup_enabled: current_organization.supplier_lookup_configured?,
          ipn_manual_entry: current_organization.ipn_generation_mode == "manual"
        }
      end
      # There's no standalone detail page anymore; send a direct visit or stale
      # bookmark to the inventory list, where the sidebar opens instead.
      format.html { redirect_to parts_path }
    end
  end

  def edit
    # JSON: the edit-part modal (opened from the list/detail pages) fetches the
    # full part on demand. HTML: the standalone edit page, kept as a fallback.
    respond_to do |format|
      format.json { render json: { part: serialize_part_full(@part) } }
      format.html do
        render inertia: "parts/edit", props: {
          part: serialize_part_full(@part),
          categories: serialize_categories,
          footprints: serialize_footprints,
          suppliers: serialize_suppliers,
          tags: serialize_tags,
          supplier_lookup_enabled: current_organization.supplier_lookup_configured?,
          ipn_manual_entry: current_organization.ipn_generation_mode == "manual"
        }
      end
    end
  end

  def create
    part = current_organization.parts.build(part_params)
    part.image_source_url = params[:image_url].presence

    if part.save
      assign_initial_stock(part)
      attach_remote_datasheet(part)
      redirect_to parts_path, notice: "Part created successfully."
    else
      # No flash alert here: the add-part modal renders these errors inline, and
      # a page-level alert would surface behind the still-open dialog instead.
      redirect_back_or_to parts_path, inertia: { errors: inertia_errors(part, as: :part) }
    end
  end

  # Queries the organization's configured supplier catalog (Mouser, ...) for a
  # manufacturer part number and returns normalized matches as JSON for the
  # add-part dialog to prefill from. Async fetch, not an Inertia visit.
  def lookup
    mpn = params[:mpn].to_s.strip
    return render(json: { error: "Enter a part number to search." }, status: :unprocessable_entity) if mpn.blank?

    results = SupplierCatalog.lookup(current_organization, mpn: mpn)
    render json: { results: results.map(&:as_json) }
  rescue SupplierCatalog::NotConfiguredError
    render json: { error: "No supplier catalog is configured. Add a Mouser or DigiKey key in Settings." }, status: :unprocessable_entity
  rescue SupplierCatalog::LookupError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def update
    @part.assign_attributes(part_params)
    # Only from a fresh catalog lookup; a plain edit doesn't send it, so an
    # existing hotlinked image is preserved.
    @part.image_source_url = params[:image_url].presence if params[:image_url].present?

    if @part.save
      attach_remote_datasheet(@part)
      # Return to wherever the edit was launched (list, detail, or the standalone
      # edit page) so the modal flow stays put instead of navigating away.
      redirect_back_or_to edit_part_path(@part), notice: "Part updated successfully."
    else
      # No page-level alert: the edit modal renders these errors inline, and one
      # would otherwise surface behind the still-open dialog.
      redirect_back_or_to edit_part_path(@part), inertia: { errors: inertia_errors(@part, as: :part) }
    end
  end

  def destroy
    if @part.destroy
      redirect_to parts_path, notice: "Part deleted successfully."
    else
      redirect_back_or_to parts_path, alert: @part.errors.full_messages.to_sentence
    end
  end

  # Bulk stock in/out for the selected parts: records the same signed movement
  # (in or out, +quantity+ units) against +storage_location_id+ for every part.
  # Each movement is independent — an "out" that would overdraw a part is skipped
  # rather than failing the whole batch, so a partial success is reported.
  def bulk_stock
    parts = current_organization.parts.where(id: bulk_part_ids)
    return redirect_to(parts_path, alert: "Select at least one part.") if parts.empty?

    location = current_organization.storage_locations.find_by(id: params[:storage_location_id])
    return redirect_to(parts_path, alert: "Choose a storage location.") unless location

    movement_type = params[:movement_type].to_s.presence_in(%w[in out])
    return redirect_to(parts_path, alert: "Choose stock in or stock out.") unless movement_type

    quantity = params[:quantity].to_i
    return redirect_to(parts_path, alert: "Enter a quantity greater than zero.") if quantity <= 0

    delta = movement_type == "out" ? -quantity : quantity
    reason = params[:reason].to_s.strip.presence || "Bulk stock #{movement_type}"

    applied = parts.count do |part|
      current_organization.stock_movements.create(
        part: part,
        storage_location: location,
        user: current_user,
        movement_type: movement_type,
        quantity_delta: delta,
        reason: reason
      ).persisted?
    end

    skipped = parts.size - applied
    notice = "Stock #{movement_type} recorded for #{applied} #{'part'.pluralize(applied)}."
    notice += " #{skipped} skipped (would go negative)." if skipped.positive?
    redirect_to parts_path, notice: notice
  end

  # Bulk relocation: for each selected part, all of its stock (across every
  # location it currently sits in) is transferred into +storage_location_id+ via
  # matching out/in ledger movements. Parts with no positive stock are left as-is.
  def bulk_move
    parts = current_organization.parts.where(id: bulk_part_ids).includes(:part_storages)
    return redirect_to(parts_path, alert: "Select at least one part.") if parts.empty?

    destination = current_organization.storage_locations.find_by(id: params[:storage_location_id])
    return redirect_to(parts_path, alert: "Choose a destination location.") unless destination

    moved = parts.count { |part| relocate_part_stock(part, destination) }

    redirect_to parts_path, notice: "Relocated stock for #{moved} #{'part'.pluralize(moved)} to #{destination.name}."
  end

  def bulk_destroy
    parts = current_organization.parts.where(id: bulk_part_ids)
    count = parts.count
    return redirect_to(parts_path, alert: "Select at least one part.") if count.zero?

    parts.destroy_all
    redirect_to parts_path, notice: "#{count} #{'part'.pluralize(count)} deleted successfully."
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

  def bulk_part_ids
    Array(params[:part_ids]).map(&:to_i).reject(&:zero?).uniq
  end

  # Moves every positive-stock location of +part+ into +destination+, recording
  # an out at the source and an in at the destination for each. Wrapped in a
  # transaction so a source is never emptied without its matching deposit. The
  # destination's own bucket is skipped (nothing to move). Returns whether any
  # stock was actually relocated.
  def relocate_part_stock(part, destination)
    moved = false

    ActiveRecord::Base.transaction do
      part.part_storages.each do |storage|
        next if storage.storage_location_id == destination.id || storage.quantity <= 0

        quantity = storage.quantity
        source = storage.storage_location

        current_organization.stock_movements.create!(
          part: part, storage_location: source, user: current_user,
          movement_type: "out", quantity_delta: -quantity, reason: "Bulk move to #{destination.name}"
        )
        current_organization.stock_movements.create!(
          part: part, storage_location: destination, user: current_user,
          movement_type: "in", quantity_delta: quantity, reason: "Bulk move from #{source.name}"
        )
        moved = true
      end
    end

    moved
  end

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

    # The import "Quantity" is the absolute stock the sheet declares for this
    # location. Reconcile it through the ledger rather than writing
    # PartStorage.quantity directly: stock_movements is the single source of
    # truth (PartStorage is maintained by StockMovement's callback), so a direct
    # write would desync the movements "Stock After" running balance. Only the
    # delta from the current level is recorded, as an adjustment.
    target = import_value(row, :quantity).to_i
    current = PartStorage.find_by(part: part, storage_location: location)&.quantity || 0
    delta = target - current
    return if delta.zero?

    StockMovement.create!(
      organization: current_organization,
      part: part,
      storage_location: location,
      user: current_user,
      movement_type: "adjustment",
      quantity_delta: delta,
      reason: "Import"
    )
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

  # Downloads+attaches the supplier datasheet when the add-part form was
  # prefilled from a catalog lookup. Runs in a background job so a slow or
  # unreachable host never stalls the request; RemoteFile guards against SSRF
  # and treats any failure as a no-op.
  #
  # The catalog image is NOT downloaded here: Mouser's image CDN sits behind
  # Akamai bot protection that serves an "Access Denied" page to any server-side
  # client. Instead we persist the source URL (see create/update) and hotlink it
  # from the browser, which is far more likely to be allowed. A manually uploaded
  # image takes precedence over the hotlink (see #part_thumbnail_url).
  def attach_remote_datasheet(part)
    datasheet_url = params[:datasheet_url].presence
    AttachRemotePartAssetsJob.perform_later(part, datasheet_url: datasheet_url) if datasheet_url
  end

  def set_part
    @part = current_organization.parts.find(params[:id])
  end

  def part_params
    params.require(:part).permit(
      :name, :mpn, :sku, :barcode, :ipn, :manufacturer, :description,
      :value, :tolerance, :voltage_rating, :power_rating, :package_type,
      :category_id, :footprint_id,
      :unit_price, :min_stock_threshold, :target_stock,
      :status, :rohs_compliant, :storage_notes,
      images: [],
      tag_ids: [],
      part_suppliers_attributes: [
        :id, :supplier_id, :supplier_sku, :unit_price, :lead_time_days,
        :url, :is_preferred, :notes, :_destroy
      ]
    )
  end

  # URL for the part's thumbnail in the list. A manually uploaded image wins
  # (local, reliable); otherwise fall back to the hotlinked supplier image URL,
  # which the browser loads directly. Returns nil when there's neither, so the
  # row shows the placeholder icon.
  #
  # For an uploaded image we serve the original blob (sized down by the browser)
  # rather than a resized variant: variants need an image processor
  # (libvips/ImageMagick) that isn't guaranteed to be installed, and a missing
  # processor turns every thumbnail into a broken image.
  def part_thumbnail_url(part)
    if part.images.attached? && part.images.first.content_type.to_s.start_with?("image/")
      rails_blob_path(part.images.first)
    else
      part.image_source_url.presence
    end
  end

  def serialize_part(part)
    {
      id: part.id,
      name: part.name,
      mpn: part.mpn,
      sku: part.sku,
      ipn: part.ipn,
      manufacturer: part.manufacturer,
      value: part.value,
      package_type: part.package_type,
      status: part.status,
      thumbnail_url: part_thumbnail_url(part),
      # Compute from the preloaded associations (see index eager-loading) rather
      # than `part.total_quantity`/`part.preferred_supplier`, which each fire a
      # fresh query per part and turn the list into an N+1.
      total_quantity: part.part_storages.to_a.sum(&:quantity),
      min_stock_threshold: part.min_stock_threshold,
      unit_price: part.unit_price&.to_f,
      location_names: part.storage_locations.map(&:name),
      supplier_name: part.part_suppliers.find(&:is_preferred)&.supplier&.name,
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
      tag_ids: part.tag_ids,
      tags: part.tags.map { |tag| { id: tag.id, name: tag.name, color: tag.color } },
      part_suppliers: part.part_suppliers.includes(:supplier).map { |ps| serialize_part_supplier(ps) }
    )
  end

  def serialize_part_storage(ps)
    location = ps.storage_location
    {
      location_id: location.id,
      location_name: location.name,
      location_path: (location.ancestors.reverse + [ location ]).map(&:name),
      quantity: ps.quantity
    }
  end

  def serialize_part_movement(movement)
    {
      id: movement.id,
      created_at: movement.created_at.iso8601,
      movement_type: movement.movement_type,
      quantity_delta: movement.quantity_delta,
      reason: movement.reason,
      location_name: movement.storage_location.name,
      user_name: movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil
    }
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
end

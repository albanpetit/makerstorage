# frozen_string_literal: true

class PartsController < ApplicationController
  include Auth
  include OptionListSerializers

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[
    create update destroy import lookup
    bulk_move bulk_update_category bulk_update_status bulk_update_tags bulk_assign_supplier
  ]
  # Bulk delete is scoped to admins/owners, not the general writer role: unlike
  # every other bulk action it's irreversible and can wipe parts org-wide, so it
  # gets the stricter gate that single-part destroy doesn't need.
  before_action :verify_organization_admin, only: %i[bulk_destroy]
  before_action :set_part, only: %i[show edit update destroy]

  # Raised when an import row's location names several zones; skips the row.
  class AmbiguousLocationError < StandardError; end

  # Part attribute => BomParser field for the optional CSV import columns.
  IMPORTED_ATTRIBUTES = {
    mpn: :mpn,
    sku: :sku,
    manufacturer: :manufacturer,
    value: :value,
    package_type: :package,
    unit_price: :unit_price,
    min_stock_threshold: :min_stock_threshold,
    status: :status
  }.freeze

  def index
    parts = current_organization.parts
      .includes(:category, :footprint, :tags, :part_storages, :storage_locations, part_suppliers: :supplier)
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
    # On a saved part, assigning tag_ids writes the tag links immediately; run the
    # whole edit in one transaction so a rejected edit doesn't keep them.
    saved = ActiveRecord::Base.transaction do
      @part.assign_attributes(part_params)
      # Only from a fresh catalog lookup; a plain edit doesn't send it, so an
      # existing hotlinked image is preserved.
      @part.image_source_url = params[:image_url].presence if params[:image_url].present?
      @part.save || raise(ActiveRecord::Rollback)
    end

    if saved
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

  # Bulk relocation: for each selected part, all of its stock (across every
  # location it currently sits in) is transferred into +storage_location_id+ via
  # matching out/in ledger movements. Parts with no positive stock are left as-is.
  def bulk_move
    parts = current_organization.parts.where(id: bulk_part_ids).includes(part_storages: :storage_location)
    return bulk_error("Select at least one part.") if parts.empty?

    destination = current_organization.storage_locations.find_by(id: params[:storage_location_id])
    return bulk_error("Choose a destination location.") unless destination

    moved = parts.count { |part| relocate_part_stock(part, destination) }

    redirect_to parts_path, notice: "Relocated stock for #{moved} #{'part'.pluralize(moved)} to #{destination.name}."
  end

  def bulk_destroy
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error("Select at least one part.") if parts.empty?

    destroyed = parts.select { |part| part.destroy }
    skipped = parts.size - destroyed.size

    notice = "#{destroyed.size} #{'part'.pluralize(destroyed.size)} deleted successfully."
    notice += " #{skipped} #{'part'.pluralize(skipped)} could not be deleted because #{skipped == 1 ? 'it has' : 'they have'} stock history or purchase orders." if skipped.positive?

    redirect_to parts_path, notice: notice
  end

  def bulk_update_category
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error("Select at least one part.") if parts.empty?

    category = current_organization.categories.find_by(id: params[:category_id])
    return bulk_error("Choose a category.") unless category

    updated = parts.update_all(category_id: category.id)
    redirect_to parts_path, notice: "Set category to #{category.name} for #{updated} #{'part'.pluralize(updated)}."
  end

  def bulk_update_status
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error("Select at least one part.") if parts.empty?

    status = params[:status].to_s
    return bulk_error("Choose a valid status.") unless Part::STATUSES.include?(status)

    updated = parts.update_all(status: status)
    redirect_to parts_path, notice: "Set status to #{status} for #{updated} #{'part'.pluralize(updated)}."
  end

  # Adds or removes the given tags on every selected part. Tags already present
  # (add) or already absent (remove) on a given part are simply left alone.
  def bulk_update_tags
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error("Select at least one part.") if parts.empty?

    tag_ids = current_organization.tags.where(id: Array(params[:tag_ids])).pluck(:id)
    return bulk_error("Choose at least one tag.") if tag_ids.empty?

    part_ids = parts.pluck(:id)

    if params[:mode] == "remove"
      PartTag.where(part_id: part_ids, tag_id: tag_ids).delete_all
      redirect_to parts_path, notice: "Removed #{tag_ids.size} #{'tag'.pluralize(tag_ids.size)} from #{part_ids.size} #{'part'.pluralize(part_ids.size)}."
    else
      # Single query for existing links instead of a per-part tag_ids lookup,
      # then a single bulk insert for whatever's missing.
      existing = PartTag.where(part_id: part_ids, tag_id: tag_ids).pluck(:part_id, :tag_id).to_set
      rows = part_ids.flat_map do |part_id|
        tag_ids.reject { |tag_id| existing.include?([ part_id, tag_id ]) }
          .map { |tag_id| { part_id: part_id, tag_id: tag_id } }
      end
      PartTag.insert_all(rows) if rows.any?
      redirect_to parts_path, notice: "Added #{tag_ids.size} #{'tag'.pluralize(tag_ids.size)} to #{part_ids.size} #{'part'.pluralize(part_ids.size)}."
    end
  end

  # Links the given supplier to every selected part, marking it preferred
  # (PartSupplier#ensure_single_preferred demotes any prior preferred link and
  # Part#sync_unit_price_from_preferred! keeps unit_price in step).
  def bulk_assign_supplier
    parts = current_organization.parts.where(id: bulk_part_ids).includes(:part_suppliers)
    return bulk_error("Select at least one part.") if parts.empty?

    supplier = current_organization.suppliers.find_by(id: params[:supplier_id])
    return bulk_error("Choose a supplier.") unless supplier

    ActiveRecord::Base.transaction do
      parts.each do |part|
        link = part.part_suppliers.to_a.find { |ps| ps.supplier_id == supplier.id } || part.part_suppliers.build(supplier: supplier)
        link.is_preferred = true
        link.save!
      end
    end

    redirect_to parts_path, notice: "Assigned #{supplier.name} as preferred supplier for #{parts.size} #{'part'.pluralize(parts.size)}."
  rescue ActiveRecord::RecordInvalid => e
    bulk_error("No supplier was assigned: #{e.record.errors.full_messages.to_sentence}.")
  end

  def import
    file = params[:file]
    return redirect_to(parts_path, alert: "Please choose a CSV file to import.") unless file

    created = 0
    updated = 0
    skipped = 0

    begin
      BomParser.each_row(file.path) do |row|
        name = import_value(row, :name)
        category_name = import_value(row, :category)

        if name.blank? || category_name.blank?
          skipped += 1
          next
        end

        part = find_existing_part(row)
        is_new = part.nil?

        # One transaction per row: a row that fails anywhere (invalid category,
        # part, location, or a stock level the ledger refuses) is skipped as a
        # whole instead of leaving a half-imported part or aborting the file.
        imported = ActiveRecord::Base.transaction do
          part ||= current_organization.parts.build(min_stock_threshold: 0, status: "active")
          part.assign_attributes(name: name, category: import_category(category_name))
          # Only what the sheet actually states: a column the file doesn't have,
          # or a blank cell, leaves an existing part's value alone instead of
          # wiping it (a re-import of a partial sheet must not erase data).
          IMPORTED_ATTRIBUTES.each do |attribute, field|
            value = import_value(row, field)
            next if value.nil?

            value = value.tr(",", ".") if attribute == :unit_price
            part.assign_attributes(attribute => value)
          end
          part.save!
          assign_stock(part, row)
          true
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, AmbiguousLocationError
          raise ActiveRecord::Rollback
        end

        if imported
          is_new ? created += 1 : updated += 1
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

  # Redirects with a flash alert AND an Inertia `errors` prop, so the client's
  # `onError` callback fires instead of `onSuccess` — without this, a rejected
  # bulk action still looks like a success to the visit that triggered it (the
  # response is a redirect either way), closing the dialog and clearing the
  # selection before the user can read why it failed.
  def bulk_error(message)
    redirect_to parts_path, alert: message, inertia: { errors: { base: message } }
  end

  # Moves every positive-stock location of +part+ into +destination+, recording
  # an out at the source and an in at the destination for each. Wrapped in a
  # transaction so a source is never emptied without its matching deposit. The
  # destination's own bucket is skipped (nothing to move). Returns whether any
  # stock was actually relocated.
  #
  # Stock that changed since the page loaded makes a movement fail validation;
  # that part's transfer is rolled back and reported as not moved rather than
  # raising.
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
  rescue ActiveRecord::RecordInvalid
    false
  end

  # Returns the first present value among the synonym columns for +field+.
  def import_value(row, field)
    BomParser.value(row, field)
  end

  def assign_stock(part, row)
    location_name = import_value(row, :location)
    quantity = import_value(row, :quantity)
    # A row naming a location without a quantity states nothing about stock:
    # leave it as is rather than reading the missing value as zero and
    # emptying the location.
    return if location_name.blank? || quantity.nil?

    location = import_location(location_name)

    # The import "Quantity" is the absolute stock the sheet declares for this
    # location. Reconcile it through the ledger rather than writing
    # PartStorage.quantity directly: stock_movements is the single source of
    # truth (PartStorage is maintained by StockMovement's callback), so a direct
    # write would desync the movements "Stock After" running balance. Only the
    # delta from the current level is recorded, as an adjustment.
    target = quantity.to_i
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

  # The sheet's category, matched regardless of case ("resistors" is the
  # existing "Resistors", not a new near-duplicate), created when missing.
  def import_category(name)
    current_organization.categories.find_by("LOWER(name) = ?", name.downcase) ||
      current_organization.categories.create!(name: name)
  end

  # Resolves the sheet's location cell to a zone: by its scanner code, by its
  # full path ("Workshop > Cabinet A > Drawer 1"), or by its bare name when only
  # one zone has it — all case-insensitively. Several zones sharing that name
  # (a "Drawer 1" in two cabinets) can't be told apart, so the row is skipped
  # rather than its stock landing in an arbitrary one. An unknown location is
  # created as a top-level shelf.
  def import_location(label)
    key = label.downcase
    zones = current_organization.storage_locations.to_a
    paths = StorageLocation.full_path_cache(current_organization.storage_locations)

    match = zones.find { |zone| zone.code.present? && zone.code.downcase == key } ||
            zones.find { |zone| zone.full_path(cache: paths).downcase == key }
    return match if match

    named = zones.select { |zone| zone.name.downcase == key }
    raise AmbiguousLocationError if named.size > 1

    named.first || current_organization.storage_locations.create!(name: label, location_type: "shelf")
  end

  def find_existing_part(row)
    mpn = import_value(row, :mpn)
    sku = import_value(row, :sku)

    # Case-insensitive, like the per-organization uniqueness of these columns:
    # otherwise a row differing only in case would be skipped as a duplicate
    # instead of updating its part.
    if mpn.present?
      current_organization.parts.find_by("LOWER(mpn) = ?", mpn.downcase)
    elsif sku.present?
      current_organization.parts.find_by("LOWER(sku) = ?", sku.downcase)
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
    permitted = params.require(:part).permit(
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
    # Through-association ids are looked up across every organization, and a
    # foreign tag then fails PartTag's validation as an exception (a 500). Keep
    # only this organization's tags.
    permitted[:tag_ids] = current_organization.tags.where(id: permitted[:tag_ids]).pluck(:id) if permitted.key?(:tag_ids)
    permitted
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
      stored_file_path_for(part.images.first)
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
      barcode: part.barcode,
      manufacturer: part.manufacturer,
      description: part.description,
      value: part.value,
      package_type: part.package_type,
      status: part.status,
      tag_names: part.tags.map(&:name),
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

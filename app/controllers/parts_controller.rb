# frozen_string_literal: true

class PartsController < ApplicationController
  include Auth
  include OptionListSerializers

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[
    create update destroy import lookup extract
    bulk_move bulk_update_category bulk_update_status bulk_update_tags bulk_assign_supplier
  ]
  # Bulk delete is scoped to admins/owners, not the general writer role: unlike
  # every other bulk action it's irreversible and can wipe parts org-wide, so it
  # gets the stricter gate that single-part destroy doesn't need.
  before_action :verify_organization_admin, only: %i[bulk_destroy]
  before_action :set_part, only: %i[show edit update destroy]

  # Each AI read is billed to the organization's own Anthropic key.
  rate_limit to: 20, within: 10.minutes, only: :extract, by: -> { current_user.id }, store: AUTH_RATE_LIMIT_STORE,
             with: -> { render json: { error: t("flash.parts.too_many_ai_reads") }, status: :too_many_requests }

  # Raised when an import row's location names several zones; skips the row.
  class AmbiguousLocationError < StandardError; end
  # Raised when an import row's quantity isn't a whole number; skips the row.
  class InvalidQuantityError < StandardError; end
  # Raised when the add-part form's opening stock can't be recorded.
  class InitialStockError < StandardError; end

  # Purchase prices shown in the part detail's price history.
  PRICE_HISTORY_LIMIT = 50

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
    query = PartsIndexQuery.new(current_organization, params)

    render inertia: "parts/index", props: {
      parts: serialize_parts_in_order(query.page_ids),
      filters: query.filters,
      pagination: query.pagination,
      facets: query.facets,
      # Parameters shown as columns: the selected category's template.
      parameter_columns: query.parameter_columns,
      total_count: query.total_count,
      total_units: query.total_units,
      # Every matching id, so "select all matching" and the "hidden by filters"
      # count work across pages without loading the parts themselves.
      matching_ids: query.matching_ids,
      # Only loaded when the CSV import dialog asks for it (to preview which
      # rows are new and which update an existing part).
      part_identifiers: InertiaRails.optional { part_identifiers },
      categories: serialize_categories,
      footprints: serialize_footprints,
      suppliers: serialize_suppliers,
      tags: serialize_tags,
      storage_locations: serialize_storage_locations,
      supplier_lookup_enabled: current_organization.supplier_lookup_configured?,
      ai_entry_enabled: current_organization.ai_entry_configured?,
      ipn_manual_entry: current_organization.ipn_generation_mode == "manual",
      bag_options: bag_options,
      bag_boxes: bag_boxes,
      open_add: params[:new].present?,
      add_prefill: add_prefill,
      # Compares every part of the organization: sent after the page has
      # rendered, so a big inventory doesn't wait on it.
      duplicate_groups_count: InertiaRails.defer { PartDuplicates.new(current_organization).count }
    }
  end

  # Full list rows for the parts a CSV export or label print needs, which may
  # sit on other pages than the one displayed: either explicit +part_ids+
  # (the selection) or every part matching the list's +filters+.
  def rows
    ids = if params.key?(:part_ids)
      current_organization.parts.where(id: Array(params[:part_ids])).alphabetical.pluck(:id)
    else
      PartsIndexQuery.new(current_organization, params.fetch(:filters, {})).matching_ids
    end

    render json: { parts: serialize_parts_in_order(ids) }
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
          # The part's own bag, then the fullest zone, first: the stock form
          # preselects the first one, never a bag another part holds.
          storages: @part.part_storages.includes(:storage_location)
            .sort_by { |ps| [ ps.storage_location_id == @part.bag_id ? 0 : 1, -ps.quantity, ps.id ] }
            .map { |ps| serialize_part_storage(ps, location_paths) },
          movements: movements.map { |movement| serialize_part_movement(movement) },
          reservations: serialize_part_reservations(@part),
          loans: serialize_part_loans(@part),
          price_history: serialize_price_history(@part),
          consumption: serialize_part_consumption(@part),
          alternatives: serialize_part_alternatives(@part),
          equivalents: PartEquivalents.new(@part).suggestions.map { |suggestion| serialize_equivalent(suggestion) },
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
      format.json { render json: { part: serialize_part_full(@part), bag_options: bag_options(@part), bag_boxes: bag_boxes } }
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
    part.image_source_url = Part.supplier_image_url(params[:image_url])
    # The datasheet read by AI-assisted entry, kept with the new part.
    part.datasheet.attach(params[:datasheet_file]) if params[:datasheet_file].is_a?(ActionDispatch::Http::UploadedFile)

    # The part, its new bag and its opening stock land together: a refused
    # stock movement must not leave the part created behind an error.
    stock_errors = []
    saved = ActiveRecord::Base.transaction do
      raise ActiveRecord::Rollback unless take_new_bag(part)

      place_in_initial_bag(part)
      raise ActiveRecord::Rollback unless part.save

      assign_initial_stock(part)
      true
    rescue InitialStockError, ActiveRecord::RecordInvalid => e
      stock_errors = e.respond_to?(:record) ? e.record.errors.full_messages : [ e.message ]
      raise ActiveRecord::Rollback
    end

    if saved
      attach_remote_datasheet(part)
      # What the add-part dialog needs to print the new part's label.
      flash[:created_part] = {
        id: part.id, name: part.name, ipn: part.ipn, mpn: part.mpn, sku: part.sku, barcode: part.barcode,
        location_names: part.storage_locations.reload.map(&:name)
      }
      # Created from a scanned supplier label: back to the scanner, on the new
      # part, ready for the next bag.
      if params[:return_to] == "scan"
        redirect_to scan_path(code: "part:#{part.id}"), notice: t("flash.parts.part_created_successfully")
      else
        redirect_to parts_path, notice: t("flash.parts.part_created_successfully")
      end
    else
      # No flash alert here: the add-part modal renders these errors inline, and
      # a page-level alert would surface behind the still-open dialog instead.
      errors = inertia_errors(part, as: :part)
      errors["initial_quantity"] = stock_errors if stock_errors.any?
      redirect_back_or_to parts_path, inertia: { errors: errors }
    end
  end

  # Queries the organization's configured supplier catalogs (Mouser, DigiKey, LCSC) for a
  # manufacturer part number and returns normalized matches as JSON for the
  # add-part dialog to prefill from. Async fetch, not an Inertia visit.
  def lookup
    mpn = params[:mpn].to_s.strip
    return render(json: { error: t("flash.parts.enter_a_part_number_to_search") }, status: :unprocessable_entity) if mpn.blank?

    results = SupplierCatalog.lookup(current_organization, mpn: mpn)
    render json: { results: results.map(&:as_json) }
  rescue SupplierCatalog::NotConfiguredError
    render json: { error: t("flash.parts.no_supplier_catalog_is_configured_add") }, status: :unprocessable_entity
  rescue SupplierCatalog::LookupError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  # AI-assisted entry: reads the photos / datasheet the add-part dialog sends
  # with the organization's Claude key (PartExtraction) and returns the fields
  # to prefill as JSON. Nothing is saved. Async fetch, not an Inertia visit.
  def extract
    result = PartExtraction.new(current_organization).extract(Array(params[:files]), hint: params[:hint])
    render json: { result: result }
  rescue PartExtraction::NotConfiguredError, PartExtraction::InvalidFileError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue PartExtraction::BusyError => e
    render json: { error: e.message }, status: :service_unavailable
  rescue PartExtraction::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def update
    # On a saved part, assigning tag_ids writes the tag links immediately; run the
    # whole edit in one transaction so a rejected edit doesn't keep them.
    saved = ActiveRecord::Base.transaction do
      @part.assign_attributes(part_params)
      raise ActiveRecord::Rollback unless take_new_bag(@part)

      previous_bag = @part.bag_id_changed? ? current_organization.storage_locations.find_by(id: @part.bag_id_in_database) : nil
      stray_bags = @part.bag_id_changed? ? stray_bags_of(@part) : []
      # Only from a fresh catalog lookup; a plain edit doesn't send it, so an
      # existing hotlinked image is preserved.
      @part.image_source_url = Part.supplier_image_url(params[:image_url]) if params[:image_url].present?
      @part.save || raise(ActiveRecord::Rollback)
      [ previous_bag, *stray_bags ].compact.each { |bag| move_stock_to_new_bag(@part, bag) } if @part.bag
      true
    rescue ActiveRecord::RecordInvalid => e
      @part.errors.add(:bag, e.record.errors.full_messages.to_sentence)
      raise ActiveRecord::Rollback
    end

    if saved
      attach_remote_datasheet(@part)
      # Return to wherever the edit was launched (list, detail, or the standalone
      # edit page) so the modal flow stays put instead of navigating away.
      redirect_back_or_to edit_part_path(@part), notice: t("flash.parts.part_updated_successfully")
    else
      # No page-level alert: the edit modal renders these errors inline, and one
      # would otherwise surface behind the still-open dialog.
      redirect_back_or_to edit_part_path(@part), inertia: { errors: inertia_errors(@part, as: :part) }
    end
  end

  def destroy
    if @part.destroy
      redirect_to parts_path, notice: t("flash.parts.part_deleted_successfully")
    else
      redirect_back_or_to parts_path, alert: @part.errors.full_messages.to_sentence
    end
  end

  # Bulk relocation: for each selected part, all of its stock (across every
  # location it currently sits in) is transferred into +storage_location_id+ via
  # matching out/in ledger movements. Parts with no positive stock are left as-is.
  def bulk_move
    parts = current_organization.parts.where(id: bulk_part_ids).includes(part_storages: :storage_location)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    destination = current_organization.storage_locations.find_by(id: params[:storage_location_id])
    return bulk_error(t("flash.parts.choose_a_destination_location")) unless destination

    moved = parts.count { |part| relocate_part_stock(part, destination) }

    redirect_back_or_to parts_path, notice: t("flash.parts.bulk_moved", count: moved, location: destination.name)
  end

  def bulk_destroy
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    destroyed = parts.select { |part| part.destroy }
    skipped = parts.size - destroyed.size

    notice = t("flash.parts.bulk_deleted", count: destroyed.size)
    notice += " #{t('flash.parts.bulk_delete_skipped', count: skipped)}" if skipped.positive?

    redirect_back_or_to parts_path, notice: notice
  end

  def bulk_update_category
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    category = current_organization.categories.find_by(id: params[:category_id])
    return bulk_error(t("flash.parts.choose_a_category")) unless category

    updated = parts.update_all(category_id: category.id, updated_at: Time.current)
    record_bulk_update(updated, "category" => category.name)
    redirect_back_or_to parts_path, notice: t("flash.parts.bulk_category", count: updated, category: category.name)
  end

  def bulk_update_status
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    status = params[:status].to_s
    return bulk_error(t("flash.parts.choose_a_valid_status")) unless Part::STATUSES.include?(status)

    updated = parts.update_all(status: status, updated_at: Time.current)
    record_bulk_update(updated, "status" => status)
    redirect_back_or_to parts_path, notice: t("flash.parts.bulk_status", count: updated, status: t("part_statuses.#{status}"))
  end

  # Adds or removes the given tags on every selected part. Tags already present
  # (add) or already absent (remove) on a given part are simply left alone.
  def bulk_update_tags
    parts = current_organization.parts.where(id: bulk_part_ids)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    tag_ids = current_organization.tags.where(id: Array(params[:tag_ids])).pluck(:id)
    return bulk_error(t("flash.parts.choose_at_least_one_tag")) if tag_ids.empty?

    part_ids = parts.pluck(:id)
    tag_names = current_organization.tags.where(id: tag_ids).order(:name).pluck(:name)

    if params[:mode] == "remove"
      PartTag.where(part_id: part_ids, tag_id: tag_ids).delete_all
      record_bulk_update(part_ids.size, "tags_removed" => tag_names)
      redirect_back_or_to parts_path, notice: t("flash.parts.bulk_tags_removed", count: part_ids.size, tags: t("flash.parts.tags", count: tag_ids.size))
    else
      # Single query for existing links instead of a per-part tag_ids lookup,
      # then a single bulk insert for whatever's missing.
      existing = PartTag.where(part_id: part_ids, tag_id: tag_ids).pluck(:part_id, :tag_id).to_set
      rows = part_ids.flat_map do |part_id|
        tag_ids.reject { |tag_id| existing.include?([ part_id, tag_id ]) }
          .map { |tag_id| { part_id: part_id, tag_id: tag_id } }
      end
      PartTag.insert_all(rows) if rows.any?
      record_bulk_update(part_ids.size, "tags_added" => tag_names)
      redirect_back_or_to parts_path, notice: t("flash.parts.bulk_tags_added", count: part_ids.size, tags: t("flash.parts.tags", count: tag_ids.size))
    end
  end

  # Links the given supplier to every selected part, marking it preferred
  # (PartSupplier#ensure_single_preferred demotes any prior preferred link and
  # Part#sync_unit_price_from_preferred! keeps unit_price in step).
  def bulk_assign_supplier
    parts = current_organization.parts.where(id: bulk_part_ids).includes(:part_suppliers)
    return bulk_error(t("flash.parts.select_at_least_one_part")) if parts.empty?

    supplier = current_organization.suppliers.find_by(id: params[:supplier_id])
    return bulk_error(t("flash.parts.choose_a_supplier")) unless supplier

    ActiveRecord::Base.transaction do
      parts.each do |part|
        link = part.part_suppliers.to_a.find { |ps| ps.supplier_id == supplier.id } || part.part_suppliers.build(supplier: supplier)
        link.is_preferred = true
        link.save!
      end
      record_bulk_update(parts.size, "supplier" => supplier.name)
    end

    redirect_back_or_to parts_path, notice: t("flash.parts.bulk_supplier", count: parts.size, supplier: supplier.name)
  rescue ActiveRecord::RecordInvalid => e
    bulk_error(t("flash.parts.no_supplier_was_assigned", errors: e.record.errors.full_messages.to_sentence))
  end

  def import
    file = params[:file]
    return redirect_to(parts_path, alert: t("flash.parts.please_choose_a_csv_file_to")) unless file
    return redirect_to(parts_path, alert: BomParser.too_large_message) if BomParser.too_large?(file)

    created = 0
    updated = 0
    skipped = 0

    begin
      # One "import" event for the file, not one per part.
      ActivityEvent.without_recording do
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
            part ||= current_organization.parts.build(min_stock_threshold: 0, status: "active", skip_bag_claim: true)
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
            claim_import_bag(part, row)
            assign_stock(part, row)
            true
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, AmbiguousLocationError, InvalidQuantityError
            raise ActiveRecord::Rollback
          end

          if imported
            is_new ? created += 1 : updated += 1
          else
            # A zone the row created was rolled back with it: reload the zone
            # index rather than hand a later row a zone that no longer exists.
            @import_zones = nil
            skipped += 1
          end
        end
      end
    rescue CSV::MalformedCSVError
      return redirect_to(parts_path, alert: t("flash.parts.could_not_parse_that_file_as"))
    end

    if created + updated > 0
      ActivityEvent.record!(current_organization, "import",
        details: { "file" => file.original_filename.to_s, "created" => created, "updated" => updated, "skipped" => skipped })
    end

    redirect_to parts_path, notice: t("flash.parts.import_complete_created_updated_skipped", created: created, updated: updated, skipped: skipped)
  end

  private

  def bulk_part_ids
    Array(params[:part_ids]).map(&:to_i).reject(&:zero?).uniq
  end

  # Bulk edits write their rows directly (update_all, insert_all) or touch
  # child rows only, so the activity log gets one summary event instead.
  def record_bulk_update(count, details)
    ActivityEvent.record!(current_organization, "update", details: { "updated" => count, **details }) if count.positive?
  end

  # Redirects with a flash alert AND an Inertia `errors` prop, so the client's
  # `onError` callback fires instead of `onSuccess` — without this, a rejected
  # bulk action still looks like a success to the visit that triggered it (the
  # response is a redirect either way), closing the dialog and clearing the
  # selection before the user can read why it failed.
  def bulk_error(message)
    redirect_back_or_to parts_path, alert: message, inertia: { errors: { base: message } }
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
          movement_type: "out", quantity_delta: -quantity, reason: "Bulk move to #{destination.name}", transfer: true
        )
        current_organization.stock_movements.create!(
          part: part, storage_location: destination, user: current_user,
          movement_type: "in", quantity_delta: quantity, reason: "Bulk move from #{source.name}", transfer: true
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
    # The quantity is the absolute stock to reach, so a cell like "n/a" or "~50"
    # must not read as 0 (to_i) and empty the location: skip the row instead.
    raise InvalidQuantityError unless quantity.match?(/\A\d+\z/)

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
  # existing "Resistors", not a new near-duplicate), created when missing. A
  # concurrent import creating the same one trips the unique index: use theirs.
  def import_category(name)
    find = -> { current_organization.categories.find_by("LOWER(name) = ?", name.downcase) }
    find.call || current_organization.categories.create!(name: name)
  rescue ActiveRecord::RecordNotUnique
    find.call || raise
  end

  # Resolves the sheet's location cell to a zone: by its scanner code, by its
  # full path ("Workshop > Cabinet A > Drawer 1"), or by its bare name when only
  # one zone has it — all case-insensitively. Several zones sharing that name
  # (a "Drawer 1" in two cabinets) can't be told apart, so the row is skipped
  # rather than its stock landing in an arbitrary one. An unknown location is
  # created as a top-level shelf.
  def import_location(label)
    key = label.downcase
    zones = import_zones

    match = zones[:by_code][key] || zones[:by_path][key]
    return match if match

    named = zones[:by_name].fetch(key, [])
    raise AmbiguousLocationError if named.size > 1

    named.first || current_organization.storage_locations.create!(name: label, location_type: "shelf").tap do |zone|
      zones[:by_path][key] = zone
      zones[:by_name][key] = [ zone ]
    end
  end

  # The organization's zones indexed by lowercased code, full path, and name,
  # loaded once per import instead of once per row.
  def import_zones
    @import_zones ||= begin
      all = current_organization.storage_locations.to_a
      paths = all.index_by(&:id)

      {
        by_code: all.select { |zone| zone.code.present? }.index_by { |zone| zone.code.downcase },
        by_path: all.each_with_object({}) { |zone, index| index[zone.full_path(cache: paths).downcase] ||= zone },
        by_name: all.group_by { |zone| zone.name.downcase }
      }
    end
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

  # The opening stock goes to the chosen zone, else (box & bag numbering) into
  # the bag the part just took.
  # Box & bag mode: a new part whose opening stock goes into a chosen zone takes
  # that zone's bag when it is one, and no bag at all when the stock goes
  # elsewhere, instead of claiming a free bag it would leave empty.
  def place_in_initial_bag(part)
    return if params[:initial_location_id].blank? || params[:initial_quantity].to_i <= 0 || part.bag_id.present?

    location = current_organization.storage_locations.find_by(id: params[:initial_location_id])
    if location&.bag? && current_organization.ipn_generation_mode == "box_bag"
      part.bag = location
    else
      part.skip_bag_claim = true
    end
  end

  # Import: a new part takes the bag its row's location names, when that's a
  # free bag, and no other one (see Part#skip_bag_claim).
  def claim_import_bag(part, row)
    return unless current_organization.ipn_generation_mode == "box_bag" && part.bag_id.nil?

    location_name = import_value(row, :location)
    return if location_name.blank?

    location = import_location(location_name)
    part.update!(bag: location) if location.bag? && current_organization.free_bags(for_part: part).exists?(id: location.id)
  end

  def assign_initial_stock(part)
    quantity = params[:initial_quantity].to_i
    return if quantity <= 0
    raise InitialStockError, t("flash.parts.quantity_is_too_large") if quantity > ApplicationRecord::MAX_INTEGER

    location = if params[:initial_location_id].present?
      current_organization.storage_locations.find_by(id: params[:initial_location_id])
    else
      part.bag
    end
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

  # What a scanned supplier label knows about a part that isn't in the
  # inventory yet (see ScansController#label_lookup), to prefill the add dialog.
  def add_prefill
    return unless params[:new].present? && params[:prefill].is_a?(ActionController::Parameters)

    prefill = params[:prefill].permit(:mpn, :manufacturer, :provider, :supplier_sku, :quantity).to_h
    prefill.transform_values { |value| value.to_s.strip.first(255) }.compact_blank.presence
  end

  def set_part
    @part = current_organization.parts.find(params[:id])
  end

  # Box & bag numbering: a part moved to another bag takes the stock it held in
  # its old one along, through the ledger.
  def move_stock_to_new_bag(part, previous_bag)
    quantity = PartStorage.find_by(part: part, storage_location: previous_bag)&.quantity.to_i
    return unless quantity.positive?

    current_organization.stock_movements.create!(
      part: part, storage_location: previous_bag, user: current_user,
      movement_type: "out", quantity_delta: -quantity, reason: "Moved to bag #{part.bag.code}", transfer: true
    )
    current_organization.stock_movements.create!(
      part: part, storage_location: part.bag, user: current_user,
      movement_type: "in", quantity_delta: quantity, reason: "Moved from bag #{previous_bag.code}", transfer: true
    )
  end

  # Box & bag numbering: the bags another part holds where this part still has
  # stock (put there by mistake). Picking a bag of its own for the part takes
  # that stock along, so a shared bag goes back to holding one component.
  def stray_bags_of(part)
    current_organization.storage_locations.bags
      .where(id: part.part_storages.where("quantity > 0").select(:storage_location_id))
      .where(id: current_organization.parts.where.not(id: part.id).where.not(bag_id: nil).select(:bag_id))
      .to_a
  end

  def box_bag_mode?
    current_organization.ipn_generation_mode == "box_bag"
  end

  # Box & bag numbering: the bags the part form offers (the free ones, counting
  # a bag only this part's stock sits in, plus the part's own), or nil when the
  # organization numbers parts another way.
  def bag_options(part = nil)
    return unless box_bag_mode?

    bags = current_organization.free_bags(for_part: part).select(:id, :code).to_a
    bags.unshift(part.bag) if part&.bag && bags.none? { |bag| bag.id == part.bag_id }
    bags.map { |bag| { id: bag.id, code: bag.code } }
  end

  # Box & bag numbering: the boxes the part form can open a new bag in (those
  # with a code, which bags are numbered from), with the code that bag gets.
  def bag_boxes
    return unless box_bag_mode?

    boxes = current_organization.storage_locations.of_type("box").where.not(code: [ nil, "" ]).alphabetical.to_a
    last_positions = current_organization.storage_locations.bags.where(parent_id: boxes.map(&:id)).group(:parent_id).maximum(:position)
    boxes.map do |box|
      next_code = StorageLocation.bag_code(box.code, last_positions.fetch(box.id, 0).to_i + 1, current_organization.ipn_separator)
      { id: box.id, name: box.name, next_code: next_code }
    end
  end

  # Box & bag numbering: `part[new_bag_box_id]` asks for a fresh bag at the end
  # of that box (instead of an existing one), which the part then takes. Runs
  # inside the save's transaction so a refused part leaves no empty bag behind.
  # Returns false, with the reason on the part's errors, when the bag can't be
  # made.
  def take_new_bag(part)
    box_id = params.dig(:part, :new_bag_box_id).presence
    return true unless box_id && box_bag_mode?

    box = current_organization.storage_locations.of_type("box").find_by(id: box_id)
    if box.nil?
      part.errors.add(:bag, :bag_other_organization)
      return false
    end

    part.bag = box.add_bags!(1).first
    true
  rescue ActiveRecord::RecordInvalid => e
    part.errors.add(:bag, e.record.errors.full_messages.to_sentence)
    false
  end

  def part_params
    permitted = params.require(:part).permit(
      :name, :mpn, :sku, :barcode, :ipn, :bag_id, :manufacturer, :description,
      :value, :tolerance, :voltage_rating, :power_rating, :package_type,
      :category_id, :footprint_id,
      :unit_price, :min_stock_threshold, :target_stock,
      :status, :rohs_compliant, :storage_notes,
      :kicad_symbol, :kicad_footprint,
      images: [],
      tag_ids: [],
      # Parameter definition id => value ("" removes it).
      parameter_values: {},
      part_suppliers_attributes: [
        :id, :supplier_id, :supplier_sku, :unit_price, :lead_time_days,
        :url, :is_preferred, :notes, :_destroy, { price_breaks: %i[quantity unit_price] }
      ]
    )
    # Through-association ids are looked up across every organization, and a
    # foreign tag then fails PartTag's validation as an exception (a 500). Keep
    # only this organization's tags.
    permitted[:tag_ids] = current_organization.tags.where(id: permitted[:tag_ids]).pluck(:id) if permitted.key?(:tag_ids)
    # Same for parameters: drop ids that aren't this organization's.
    if permitted.key?(:parameter_values)
      values = permitted[:parameter_values].to_h
      owned = current_organization.parameter_definitions.where(id: values.keys.map(&:to_i)).pluck(:id).to_set
      permitted[:parameter_values] = values.select { |id, _| owned.include?(id.to_i) }
    end
    # In box & bag mode the IPN is the bag's code: pick the bag, not the IPN.
    # Other modes don't use bags at all.
    if box_bag_mode?
      permitted.delete(:ipn)
      permitted[:bag_id] = permitted[:bag_id].presence if permitted.key?(:bag_id)
    else
      permitted.delete(:bag_id)
    end
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
      part.hotlinked_image_url
    end
  end

  # Serializes the parts with +ids+ (already scoped to the organization) in
  # the order given, with the associations serialize_part reads preloaded.
  def serialize_parts_in_order(ids)
    parts = current_organization.parts.where(id: ids)
      .includes(:category, :footprint, :tags, :part_storages, :storage_locations, part_suppliers: :supplier,
                part_parameters: :parameter_definition)
      .with_attached_images
      .index_by(&:id)
    ids.filter_map { |id| parts[id] }.map { |part| serialize_part(part) }
  end

  def part_identifiers
    rows = current_organization.parts.pluck(:mpn, :sku)
    { mpns: rows.filter_map { |mpn, _| mpn.presence }.uniq, skus: rows.filter_map { |_, sku| sku.presence }.uniq }
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
      footprint: part.footprint ? { id: part.footprint.id, name: part.footprint.name } : nil,
      parameters: serialize_part_parameters(part)
    }
  end

  def serialize_part_parameters(part)
    part.part_parameters.sort_by { |parameter| parameter.name.downcase }.map do |parameter|
      { id: parameter.parameter_definition_id, name: parameter.name, value: parameter.value, display: parameter.display_value }
    end
  end

  # Confirmed projects holding this part, directly or through their
  # sub-assemblies (empty when reservations are off).
  def serialize_part_reservations(part)
    Project.reservations_of(current_organization, part).map do |project, quantity|
      { project_id: project.id, reference: project.reference, name: project.name, quantity: quantity }
    end
  end

  # Parts linked as alternatives (PartAlternative), the most in stock first.
  def serialize_part_alternatives(part)
    links = part.alternative_links.to_a
    others = current_organization.parts.where(id: links.map { |link| link.other_id(part.id) })
      .includes(:footprint, :part_storages).index_by(&:id)
    links.filter_map do |link|
      other = others[link.other_id(part.id)]
      other && { id: link.id, note: link.note, part: serialize_alternative_part(other) }
    end.sort_by { |entry| [ -entry[:part][:total_quantity], entry[:part][:name].downcase ] }
  end

  def serialize_equivalent(suggestion)
    {
      part: serialize_alternative_part(suggestion.part),
      matched: suggestion.matched,
      better: suggestion.better,
      missing: suggestion.missing
    }
  end

  def serialize_alternative_part(part)
    {
      id: part.id,
      reference: part.reference,
      name: part.name,
      mpn: part.mpn,
      manufacturer: part.manufacturer,
      value: part.value,
      footprint: part.footprint&.name,
      status: part.status,
      total_quantity: part.part_storages.sum(&:quantity)
    }
  end

  # Open loans holding some of this part, oldest first.
  def serialize_part_loans(part)
    today = current_organization.local_date
    part.loan_lines.outstanding.joins(:loan).merge(Loan.active).includes(:loan).order("loans.created_at", :id)
      .group_by(&:loan)
      .map do |loan, lines|
        { loan_id: loan.id, reference: loan.reference, borrower_name: loan.borrower_name,
          quantity: lines.sum(&:outstanding_quantity), due_on: loan.due_on&.iso8601, overdue: loan.overdue?(today) }
      end
  end

  # The part's purchase prices, oldest first (the last PRICE_HISTORY_LIMIT).
  def serialize_price_history(part)
    part.purchase_price_lines(:desc).limit(PRICE_HISTORY_LIMIT).reverse.map do |line|
      order = line.order
      {
        order_id: order.id,
        order_reference: order.reference,
        status: order.status,
        supplier_name: order.supplier.name,
        date: (order.ordered_at || order.created_at.to_date).iso8601,
        quantity: line.quantity,
        unit_price: line.unit_price.to_f
      }
    end
  end

  # Usage over the organization's window and the threshold it suggests
  # (PartConsumption), plus the last months for the sparkline.
  def serialize_part_consumption(part)
    consumption = PartConsumption.new(current_organization)
    entry = consumption.for_part(part)

    {
      window_days: consumption.window_days,
      consumed: entry&.consumed || 0,
      movements: entry&.movements || 0,
      monthly_rate: entry ? entry.monthly_rate.round(1) : 0,
      days_left: entry&.days_left(part.total_quantity),
      cover_days: entry&.cover_days,
      suggested_threshold: entry&.suggested_threshold,
      last_used_at: entry&.last_used_at&.iso8601,
      months: consumption.monthly(part)
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
      kicad_symbol: part.kicad_symbol,
      kicad_footprint: part.kicad_footprint,
      category_id: part.category_id,
      footprint_id: part.footprint_id,
      bag_id: part.bag_id,
      tag_ids: part.tag_ids,
      tags: part.tags.map { |tag| { id: tag.id, name: tag.name, color: tag.color } },
      part_suppliers: part.part_suppliers.includes(:supplier).map { |ps| serialize_part_supplier(ps) },
      files: serialize_part_files(part)
    )
  end

  # The datasheet first, then the other files in the order they were added.
  def serialize_part_files(part)
    files = part.attachments_attachments.includes(:blob).order(:created_at, :id).to_a
    files.unshift(part.datasheet_attachment) if part.datasheet.attached?
    files.map do |file|
      {
        id: file.id,
        filename: file.filename.to_s,
        content_type: file.content_type,
        byte_size: file.byte_size,
        created_at: file.created_at.iso8601,
        url: stored_file_path_for(file),
        datasheet: file.name == "datasheet"
      }
    end
  end

  def serialize_part_storage(ps, paths)
    location = ps.storage_location
    {
      location_id: location.id,
      location_name: location.name,
      location_path: location.path_names(cache: paths),
      quantity: ps.quantity
    }
  end

  # id => zone map so each storage's path resolves in memory, not a query per level.
  def location_paths
    @location_paths ||= StorageLocation.full_path_cache(current_organization.storage_locations)
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
      notes: ps.notes,
      price_breaks: ps.price_breaks_for_json
    }
  end
end

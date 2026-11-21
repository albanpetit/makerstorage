# frozen_string_literal: true

# Creates or updates an organization's parts from a CSV sheet (Inventory →
# Import), one transaction per row: a row that fails anywhere (invalid
# category, part, location, or a stock level the ledger refuses) is skipped as
# a whole instead of leaving a half-imported part or aborting the file.
#
#   result = PartCsvImport.new(organization, user).call(path) { |processed| … }
#   result.created # => 12
#
# Columns are matched by BomParser (French and English headers). A part is
# found by MPN, else SKU (case-insensitively), else created. Only what the
# sheet states is written: a missing column or a blank cell leaves an existing
# part's value alone. "Location" + "Quantity" is the absolute stock to reach in
# that zone, reached through an adjustment movement. Run by PartCsvImportJob;
# raises CSV::MalformedCSVError on an unreadable file.
class PartCsvImport
  # Raised when a row's location names several zones; skips the row.
  class AmbiguousLocationError < StandardError; end
  # Raised when a row's quantity isn't a whole number; skips the row.
  class InvalidQuantityError < StandardError; end

  # Part attribute => BomParser field for the optional columns.
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

  # How often (in rows) the block passed to #call hears about progress.
  PROGRESS_EVERY = 100

  Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

  def initialize(organization, user)
    @organization = organization
    @user = user
  end

  # Rows in the file at +path+ (header excluded).
  def self.count_rows(path)
    count = 0
    BomParser.each_row(path) { count += 1 }
    count
  end

  def call(path)
    result = Result.new(created: 0, updated: 0, skipped: 0)
    processed = 0

    # One "import" event for the file (written by the caller), not one per part.
    ActivityEvent.without_recording do
      BomParser.each_row(path) do |row|
        case import_row(row)
        when :created then result.created += 1
        when :updated then result.updated += 1
        else result.skipped += 1
        end
        processed += 1
        yield processed, result if block_given? && (processed % PROGRESS_EVERY).zero?
      end
    end
    result
  end

  private

  attr_reader :organization, :user

  def import_row(row)
    name = value(row, :name)
    category_name = value(row, :category)
    return :skipped if name.blank? || category_name.blank?

    part = find_existing_part(row)
    is_new = part.nil?

    imported = ActiveRecord::Base.transaction do
      part ||= organization.parts.build(min_stock_threshold: 0, status: "active", skip_bag_claim: true)
      part.assign_attributes(name: name, category: category(category_name))
      IMPORTED_ATTRIBUTES.each do |attribute, field|
        text = value(row, field)
        next if text.nil?

        text = text.tr(",", ".") if attribute == :unit_price
        part.assign_attributes(attribute => text)
      end
      part.save!
      claim_bag(part, row)
      assign_stock(part, row)
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, AmbiguousLocationError, InvalidQuantityError
      raise ActiveRecord::Rollback
    end

    if imported
      is_new ? :created : :updated
    else
      # A zone or category the row created was rolled back with it: reload
      # them rather than hand a later row a record that no longer exists.
      @zones = nil
      @categories = nil
      :skipped
    end
  end

  # The first present value among the synonym columns for +field+.
  def value(row, field)
    BomParser.value(row, field)
  end

  def find_existing_part(row)
    mpn = value(row, :mpn)
    sku = value(row, :sku)

    # Case-insensitive, like the per-organization uniqueness of these columns:
    # otherwise a row differing only in case would be skipped as a duplicate
    # instead of updating its part.
    if mpn.present?
      organization.parts.find_by("LOWER(mpn) = ?", mpn.downcase)
    elsif sku.present?
      organization.parts.find_by("LOWER(sku) = ?", sku.downcase)
    end
  end

  # The sheet's category, matched regardless of case ("resistors" is the
  # existing "Resistors", not a new near-duplicate), created when missing. A
  # concurrent import creating the same one trips the unique index: use theirs.
  def category(name)
    key = name.downcase
    categories[key] ||= begin
      organization.categories.create!(name: name)
    rescue ActiveRecord::RecordNotUnique
      organization.categories.find_by("LOWER(name) = ?", key) || raise
    end
  end

  # Categories by lowercased name, loaded once per import.
  def categories
    @categories ||= organization.categories.to_a.index_by { |category| category.name.downcase }
  end

  def assign_stock(part, row)
    location_name = value(row, :location)
    quantity = value(row, :quantity)
    # A row naming a location without a quantity states nothing about stock:
    # leave it as is rather than reading the missing value as zero and
    # emptying the location.
    return if location_name.blank? || quantity.nil?
    # The quantity is the absolute stock to reach, so a cell like "n/a" or "~50"
    # must not read as 0 (to_i) and empty the location: skip the row instead.
    raise InvalidQuantityError unless quantity.match?(/\A\d+\z/)

    location = location(location_name)

    # Reconciled through the ledger (stock_movements is the single source of
    # truth, PartStorage follows it): only the delta from the current level is
    # recorded, as an adjustment.
    target = Quantity.parse(quantity) || 0
    current = PartStorage.find_by(part: part, storage_location: location)&.quantity || 0
    delta = Quantity.sum(target, -current)
    return if delta.zero?

    StockMovement.create!(
      organization: organization, part: part, storage_location: location, user: user,
      movement_type: "adjustment", quantity_delta: delta, reason: "Import"
    )
  end

  # Box & bag numbering: a new part takes the bag its row's location names,
  # when that's a free bag, and no other one (see Part#skip_bag_claim).
  def claim_bag(part, row)
    return unless organization.ipn_generation_mode == "box_bag" && part.bag_id.nil?

    location_name = value(row, :location)
    return if location_name.blank?

    zone = location(location_name)
    part.update!(bag: zone) if zone.bag? && organization.free_bags(for_part: part).exists?(id: zone.id)
  end

  # Resolves the sheet's location cell to a zone: by its scanner code, by its
  # full path ("Workshop > Cabinet A > Drawer 1"), or by its bare name when only
  # one zone has it, all case-insensitively. Several zones sharing that name
  # (a "Drawer 1" in two cabinets) can't be told apart, so the row is skipped
  # rather than its stock landing in an arbitrary one. An unknown location is
  # created as a top-level shelf.
  def location(label)
    key = label.downcase
    match = zones[:by_code][key] || zones[:by_path][key]
    return match if match

    named = zones[:by_name].fetch(key, [])
    raise AmbiguousLocationError if named.size > 1

    named.first || organization.storage_locations.create!(name: label, location_type: "shelf").tap do |zone|
      zones[:by_path][key] = zone
      zones[:by_name][key] = [ zone ]
    end
  end

  # The organization's zones indexed by lowercased code, full path and name,
  # loaded once per import instead of once per row.
  def zones
    @zones ||= begin
      all = organization.storage_locations.to_a
      paths = all.index_by(&:id)

      {
        by_code: all.select { |zone| zone.code.present? }.index_by { |zone| zone.code.downcase },
        by_path: all.each_with_object({}) { |zone, index| index[zone.full_path(cache: paths).downcase] ||= zone },
        by_name: all.group_by { |zone| zone.name.downcase }
      }
    end
  end
end

# Merges duplicate parts into the one to keep: everything hanging off the
# duplicates moves to the kept part, then the duplicates are deleted.
#
#   result = PartMerge.new(keep: part, duplicates: [other], user: current_user).merge!
#
# Rows are moved in place (ids, timestamps and ledger kept), so the kept part's
# stock still adds up to its movements:
#
#   stock        each zone's quantity is added to the kept part's row there
#   movements    the whole ledger moves (the kept part's history shows both)
#   orders       order lines move; on an order that already has a line for the
#                kept part the two are combined into one (quantities added),
#                keeping their zone split only when both lines had one
#   projects     BOM lines point to the kept part
#   stocktakes   count lines move; two lines of one count on the same zone
#                become one, adding up what each expected and counted
#   loans        loan lines point to the kept part
#   tags         union
#   parameters   union; on a parameter both parts have, the kept part's value
#                stays
#   suppliers    links move; on a supplier both parts are linked to, the kept
#                part's link stays and takes the duplicate's blank fields; a
#                preferred link only stays preferred if the kept part had none
#   files        images and attached files move; a datasheet joins the kept
#                part's files when it already has one
#   details      the kept part's own details win; its blank fields (MPN, SKU,
#                barcode, manufacturer, value, footprint, description, price…)
#                are filled from the duplicates, in the order given
#   bags         box & bag numbering: a kept part without a bag takes the first
#                duplicate's bag (and its code as IPN); stock left in the other
#                duplicates' bags is moved into the kept part's bag through the
#                ledger, so each bag still holds one component
#
# Parts counted in different units (pieces and meters) are never merged.
# Everything runs in one transaction.
class PartMerge
  class Error < StandardError; end

  Result = Data.define(:kept, :merged_count, :stock_rows, :movements, :order_lines, :project_lines)

  # Detail columns copied from a duplicate when the kept part leaves them blank.
  FILLED_ATTRIBUTES = %i[
    mpn sku barcode manufacturer description value footprint_id package_type tolerance power_rating voltage_rating
    unit_price lead_time_days target_stock storage_notes image_source_url kicad_symbol kicad_footprint
  ].freeze
  # Unique per organization: cleared on the duplicate before the kept part takes them.
  UNIQUE_ATTRIBUTES = %i[mpn sku barcode ipn].freeze

  # Moves everything that references part +from+ onto part +to+ (both ids),
  # leaving +from+ with nothing attached so it can be deleted. Shared with
  # OrganizationMerge, which folds parts the same way. Returns the moved row
  # counts as { stock_rows:, movements:, order_lines:, project_lines: }.
  def self.fold(from, to)
    counts = { stock_rows: 0 }

    PartStorage.where(part_id: from).find_each do |storage|
      existing = PartStorage.find_by(part_id: to, storage_location_id: storage.storage_location_id)
      if existing
        existing.update_columns(quantity: existing.quantity + storage.quantity, updated_at: Time.current)
        storage.delete
      else
        storage.update_columns(part_id: to)
      end
      counts[:stock_rows] += 1
    end

    counts[:movements] = StockMovement.where(part_id: from).update_all(part_id: to)
    counts[:order_lines] = fold_order_lines(from, to)
    counts[:project_lines] = ProjectLine.where(part_id: from).update_all(part_id: to)
    fold_stocktake_lines(from, to)
    LoanLine.where(part_id: from).update_all(part_id: to)
    repoint_links(PartTag, :part_id, from, to, :tag_id)
    repoint_links(PartParameter, :part_id, from, to, :parameter_definition_id)
    fold_supplier_links(from, to)
    move_attachments(from, to, "images")
    move_attachments(from, to, "datasheet", else_as: "attachments")
    move_attachments(from, to, "attachments")
    PartDuplicateDismissal.where(part_id: from).or(PartDuplicateDismissal.where(other_part_id: from)).delete_all
    counts
  end

  # Points the join rows of +from+ at +to+, dropping those that would link the
  # same record twice (+other+ is the join's other side).
  def self.repoint_links(model, column, from, to, other)
    model.where(column => from, other => model.where(column => to).select(other)).delete_all
    model.where(column => from).update_all(column => to)
  end

  # An order holds one line per part: a line of +from+ on an order that already
  # has one for +to+ is added to it. Returns how many lines moved or combined.
  def self.fold_order_lines(from, to)
    OrderLine.where(part_id: from).includes(:allocations).find_each.count do |line|
      kept = OrderLine.includes(:allocations).find_by(order_id: line.order_id, part_id: to)
      if kept.nil?
        line.update_columns(part_id: to)
        next true
      end

      # update_columns skips the after_update that drops a split on a quantity
      # change: the split is kept only when both lines had one (it then still
      # adds up to the combined quantity).
      if kept.allocations.any? && line.allocations.any?
        line.allocations.each do |allocation|
          same_zone = kept.allocations.find { |a| a.storage_location_id == allocation.storage_location_id }
          if same_zone
            same_zone.update_columns(quantity: same_zone.quantity + allocation.quantity)
          else
            allocation.update_columns(order_line_id: kept.id)
          end
        end
      else
        OrderLineAllocation.where(order_line_id: [ kept.id, line.id ]).delete_all
      end
      kept.update_columns(quantity: kept.quantity + line.quantity, unit_price: kept.unit_price || line.unit_price,
                          updated_at: Time.current)
      OrderLineAllocation.where(order_line_id: line.id).delete_all
      line.delete
      true
    end
  end

  # Two parts folded together can sit on the same zone of one stocktake: their
  # lines become one, adding up what each expected and counted.
  def self.fold_stocktake_lines(from, to)
    StocktakeLine.where(part_id: from).find_each do |line|
      existing = StocktakeLine.find_by(stocktake_id: line.stocktake_id, part_id: to, storage_location_id: line.storage_location_id)
      unless existing
        line.update_columns(part_id: to)
        next
      end

      counted = [ existing.counted_quantity, line.counted_quantity ].compact
      existing.update_columns(expected_quantity: existing.expected_quantity + line.expected_quantity,
                              counted_quantity: counted.empty? ? nil : counted.sum,
                              stock_movement_id: existing.stock_movement_id || line.stock_movement_id)
      line.delete
    end
  end

  def self.fold_supplier_links(from, to)
    has_preferred = PartSupplier.exists?(part_id: to, is_preferred: true)
    kept_links = PartSupplier.where(part_id: to).index_by(&:supplier_id)

    PartSupplier.where(part_id: from).find_each do |link|
      kept = kept_links[link.supplier_id]
      if kept
        blanks = %i[supplier_sku url unit_price price_breaks lead_time_days notes].select { |column| kept[column].blank? && link[column].present? }
        kept.update_columns(blanks.to_h { |column| [ column, link[column] ] }) if blanks.any?
        link.delete
      else
        link.update_columns(part_id: to, is_preferred: link.is_preferred && !has_preferred)
        has_preferred ||= link.is_preferred
      end
    end
  end

  # Moves +from+'s files of attachment +name+ to +to+. A single attachment the
  # kept part already has is filed under +else_as+ instead, or else stays
  # where it is (and is deleted with +from+).
  def self.move_attachments(from, to, name, else_as: nil)
    single = Part.reflect_on_attachment(name).macro == :has_one_attached
    taken = single && ActiveStorage::Attachment.exists?(record_type: "Part", record_id: to, name: name)
    return if taken && else_as.nil?

    ActiveStorage::Attachment.where(record_type: "Part", record_id: from, name: name)
      .update_all(record_id: to, name: taken ? else_as : name)
  end

  def initialize(keep:, duplicates:, user: nil)
    @keep = keep
    @duplicates = duplicates.reject { |part| part.id == keep.id }.uniq(&:id)
    @user = user
  end

  def merge!
    validate!
    totals = Hash.new(0)

    ActiveRecord::Base.transaction do
      organization.lock!
      keep.reload
      merged_labels = duplicates.map { |duplicate| ActivityEvent.label_for(duplicate) }

      # One "merge" event rather than an update and a deletion per part.
      ActivityEvent.without_recording do
        fill_details

        duplicates.each do |duplicate|
          duplicate.reload
          bag = duplicate.bag
          duplicate.update_columns(bag_id: nil, bag_assigned_at: nil, ipn: nil)
          self.class.fold(duplicate.id, keep.id).each { |key, count| totals[key] += count }
          take_bag(bag) if bag
          duplicate.reload.destroy!
        end
        keep.sync_unit_price_from_preferred!
      end
      ActivityEvent.record!(organization, "merge", keep, details: { "merged" => merged_labels })
    end

    Result.new(kept: keep.reload, merged_count: duplicates.size, **%i[stock_rows movements order_lines project_lines].to_h { |key| [ key, totals[key] ] })
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => e
    raise Error, I18n.t("errors.part_merge.failed", error: e.message)
  end

  private

  attr_reader :keep, :duplicates, :user

  def organization
    keep.organization
  end

  def validate!
    raise Error, I18n.t("errors.part_merge.pick_one") if duplicates.empty?
    raise Error, I18n.t("errors.part_merge.other_organization") if duplicates.any? { |part| part.organization_id != keep.organization_id }

    units = duplicates.map(&:unit).uniq - [ keep.unit ]
    return if units.empty?

    raise Error, I18n.t("errors.part_merge.units", units: ([ keep.unit ] + units).join(", "))
  end

  # The kept part's blank details come from the duplicates (first one wins).
  # Unique identifiers are freed on the duplicates first.
  def fill_details
    updates = {}
    duplicates.each do |duplicate|
      FILLED_ATTRIBUTES.each do |column|
        updates[column] = duplicate[column] if keep[column].blank? && updates[column].blank? && duplicate[column].present?
      end
    end
    if keep.min_stock_threshold.zero?
      threshold = duplicates.map(&:min_stock_threshold).max
      updates[:min_stock_threshold] = threshold if threshold.positive?
    end
    if keep.ipn.blank? && keep.bag_id.nil? && organization.ipn_generation_mode != "box_bag"
      updates[:ipn] = duplicates.filter_map { |duplicate| duplicate.ipn.presence }.first
    end
    updates.compact!
    return if updates.empty?

    freed = (UNIQUE_ATTRIBUTES & updates.keys).to_h { |column| [ column, nil ] }
    Part.where(id: duplicates.map(&:id)).update_all(freed) if freed.any?
    keep.update_columns(updates.merge(updated_at: Time.current))
  end

  # Box & bag numbering: the kept part takes a duplicate's bag when it has none;
  # otherwise the stock left in that bag joins the kept part's own bag.
  def take_bag(bag)
    if keep.bag_id.nil?
      keep.update_columns(bag_id: bag.id, bag_assigned_at: Time.current, ipn: bag.code)
      return
    end

    quantity = PartStorage.find_by(part_id: keep.id, storage_location_id: bag.id)&.quantity.to_i
    return unless quantity.positive?

    reason = "Merged duplicate: moved from bag #{bag.code} to #{keep.bag.code}"
    organization.stock_movements.create!(part: keep, storage_location: bag, user: user,
                                         movement_type: "out", quantity_delta: -quantity, reason: reason)
    organization.stock_movements.create!(part: keep, storage_location: keep.bag, user: user,
                                         movement_type: "in", quantity_delta: quantity, reason: reason)
  end
end

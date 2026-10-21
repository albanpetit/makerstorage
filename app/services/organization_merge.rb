# Merges one organization (the source) into another (the target): every
# inventory record of the source moves to the target, then the source is
# deleted. The target keeps its own settings, integrations, label printers
# and logo.
#
#   result = OrganizationMerge.new(source: org_a, target: org_b).merge!
#
# Rows are moved in place (their ids, timestamps, files and ledger stay as they
# are), so stock levels still add up to the movements behind them. What would
# clash in the target is resolved rather than refused:
#
#   categories   same name (any case) as a target category: the target's is
#                kept and the source's parts and sub-categories move under it;
#                a code already used in the target is cleared
#   footprints   same name: the target's is kept
#   tags         same name: the target's is kept
#   suppliers    same catalog provider (Mouser, DigiKey) or same name (any
#                case): the target's is kept, with the source's part links and
#                orders
#   zones        never merged (two zones with the same name may be different
#                places); a code already used in the target gets a number
#                appended ("A" → "A2"), and bag codes follow their box with the
#                target's IPN separator
#   parts        same MPN, SKU or barcode (any case) as a target part: one part
#                with the stock, movements, order and project lines, tags,
#                suppliers and files of both; the target's details are kept
#   IPNs         a moved part whose IPN is already taken gets a new one from the
#                target's numbering (left blank in manual and box & bag modes)
#   references   an order or project reference already used gets a suffix
#   members      the source's members join the target with their role (owners
#                as admins); members already there keep theirs
#
# Everything runs in one transaction: a failure leaves both organizations as
# they were.
class OrganizationMerge
  class Error < StandardError; end

  Result = Data.define(:parts_moved, :parts_merged, :codes_renamed, :ipns_cleared, :ipns_reassigned, :members_added)

  def initialize(source:, target:)
    @source = source
    @target = target
  end

  def merge!
    raise Error, "An organization can't be merged into itself." if source.id == target.id
    raise Error, "A personal organization can't be merged into another one." if source.personal?

    @codes_renamed = 0
    result = ActiveRecord::Base.transaction do
      target.lock!
      source.lock!

      category_ids = merge_categories
      footprint_ids = merge_by_name(Footprint)
      tag_ids = merge_by_name(Tag)
      supplier_ids = merge_suppliers

      category_ids.each { |from, to| Part.where(category_id: from).update_all(category_id: to) }
      footprint_ids.each do |from, to|
        Part.where(footprint_id: from).update_all(footprint_id: to)
        move_attachments("Footprint", from, to, "image")
      end
      tag_ids.each { |from, to| repoint_links(PartTag, :tag_id, from, to, :part_id) }
      supplier_ids.each do |from, to|
        repoint_links(PartSupplier, :supplier_id, from, to, :part_id)
        Order.where(supplier_id: from).update_all(supplier_id: to)
        move_attachments("Supplier", from, to, "logo")
      end

      move_storage_locations
      moved, merged, cleared = merge_parts
      StockMovement.where(organization_id: source.id).update_all(organization_id: target.id)
      move_with_references(Order)
      move_with_references(Project)
      members_added = add_members

      source.reload.destroy!
      reassigned = reassign_ipns(cleared)

      Result.new(parts_moved: moved, parts_merged: merged, codes_renamed: @codes_renamed,
                 ipns_cleared: cleared.size, ipns_reassigned: reassigned, members_added: members_added)
    end
    target.reload
    result
  rescue ActiveRecord::RecordNotDestroyed
    raise Error, "#{source.name} could not be deleted once its data was moved."
  end

  private

  attr_reader :source, :target

  # -- Reference data --------------------------------------------------------

  # Moves the source categories that have no namesake in the target, and
  # returns the others as source id => target id. Sub-categories of a merged
  # category hang under its target namesake.
  def merge_categories
    existing = target.categories.pluck(:name, :id).to_h { |name, id| [ name.downcase, id ] }
    codes = target.categories.where.not(code: [ nil, "" ]).pluck(:code).to_set { |code| code.downcase }
    merged = {}

    source.categories.order(:id).pluck(:id, :name, :code).each do |id, name, code|
      if (match = existing[name.downcase])
        merged[id] = match
        next
      end

      updates = { organization_id: target.id }
      updates[:code] = nil if code.present? && !codes.add?(code.downcase)
      Category.where(id: id).update_all(updates)
    end

    merged.each do |from, to|
      Category.where(parent_id: from, organization_id: target.id).update_all(parent_id: to)
    end
    merged
  end

  # Moves the source records of +model+ whose name has no exact match in the
  # target (footprint and tag names are unique as typed) and returns the others
  # as source id => target id.
  def merge_by_name(model)
    existing = model.where(organization_id: target.id).pluck(:name, :id).to_h
    merged = {}

    model.where(organization_id: source.id).pluck(:id, :name).each do |id, name|
      if (match = existing[name])
        merged[id] = match
      else
        model.where(id: id).update_all(organization_id: target.id)
      end
    end
    merged
  end

  # Catalog suppliers match on their provider, the others on their name.
  def merge_suppliers
    providers = target.suppliers.where.not(catalog_provider: nil).pluck(:catalog_provider, :id).to_h
    names = target.suppliers.pluck(:name, :id).to_h { |name, id| [ name.downcase, id ] }
    merged = {}

    source.suppliers.pluck(:id, :name, :catalog_provider).each do |id, name, provider|
      match = provider ? providers[provider] : names[name.downcase]
      if match
        merged[id] = match
      else
        Supplier.where(id: id).update_all(organization_id: target.id)
      end
    end
    merged
  end

  # Points the join rows of +from+ at +to+, dropping those that would link the
  # same record twice (+other+ is the join's other side).
  def repoint_links(model, column, from, to, other)
    model.where(column => from, other => model.where(column => to).select(other)).delete_all
    model.where(column => from).update_all(column => to)
  end

  # Moves +from+'s files of attachment +name+ to +to+. A single attachment the
  # target already has stays where it is (and goes with the source record).
  def move_attachments(record_type, from, to, name)
    single = record_type.constantize.reflect_on_attachment(name).macro == :has_one_attached
    return if single && ActiveStorage::Attachment.exists?(record_type: record_type, record_id: to, name: name)

    ActiveStorage::Attachment.where(record_type: record_type, record_id: from, name: name).update_all(record_id: to)
  end

  # -- Zones -----------------------------------------------------------------

  # Moves every zone, giving a free code to those whose code the target already
  # uses (a zone's code or a part's IPN, since a bag's code becomes the IPN of
  # the part holding it). A box is renamed until its bags' codes are free too.
  def move_storage_locations
    zones = source.storage_locations.to_a
    bags_by_box = zones.select(&:bag?).group_by(&:parent_id)
    boxes = zones.select { |zone| zone.box? && zone.code.present? && bags_by_box.key?(zone.id) }
    separator = target.ipn_separator
    occupants = source.parts.where.not(bag_id: nil).pluck(:bag_id, :id, :ipn).to_h { |bag_id, id, ipn| [ bag_id, [ id, ipn ] ] }

    taken = Set.new
    target.storage_locations.where.not(code: [ nil, "" ]).pluck(:code).each { |code| taken << code.downcase }
    target.parts.where.not(ipn: nil).pluck(:ipn).each { |ipn| taken << ipn.downcase }
    new_codes = {}

    boxes.each do |box|
      positions = bags_by_box[box.id].filter_map(&:position)
      code = free_code(box.code, taken) { |candidate| [ candidate ] + positions.map { |p| StorageLocation.bag_code(candidate, p, separator) } }
      new_codes[box.id] = code
      bags_by_box[box.id].each do |bag|
        new_codes[bag.id] = StorageLocation.bag_code(code, bag.position, separator) if bag.position
      end
    end

    zones.each do |zone|
      next if new_codes.key?(zone.id) || zone.code.blank?

      new_codes[zone.id] = free_code(zone.code, taken) { |candidate| [ candidate ] }
    end

    StorageLocation.where(organization_id: source.id).update_all(organization_id: target.id)
    zones.each do |zone|
      code = new_codes[zone.id]
      next if code.nil? || code == zone.code

      StorageLocation.where(id: zone.id).update_all(code: code)
      @codes_renamed += 1 unless zone.bag?
      occupant_id, ipn = occupants[zone.id]
      Part.where(id: occupant_id).update_all(ipn: code) if occupant_id && ipn.to_s.casecmp?(zone.code.to_s)
    end
  end

  # +base+, or +base+ followed by the first number from 2 ("A2", "T1-2") for
  # which none of the codes the block derives from it is in +taken+ (lowercase;
  # it then holds them too).
  def free_code(base, taken)
    candidate = base
    joiner = base.match?(/\d\z/) ? "-" : ""
    suffix = 1
    while (codes = yield(candidate).map(&:downcase)).any? { |code| taken.include?(code) }
      suffix += 1
      candidate = "#{base}#{joiner}#{suffix}"
    end
    taken.merge(codes)
    candidate
  end

  # -- Parts -----------------------------------------------------------------

  # Moves the parts with no counterpart in the target and folds the others
  # into theirs. Returns [moved count, merged count, ids of moved parts whose
  # IPN was taken (cleared, to be renumbered)].
  def merge_parts
    keys = %i[mpn sku barcode]
    index = keys.to_h { |key| [ key, {} ] }
    target.parts.pluck(:id, *keys).each do |id, *values|
      keys.zip(values).each { |key, value| index[key][value.downcase] ||= id if value.present? }
    end
    taken_ipns = target.parts.where.not(ipn: nil).pluck(:ipn).to_set(&:downcase)

    merged = {}
    moving = []
    cleared = []
    source.parts.pluck(:id, :ipn, *keys).each do |id, ipn, *values|
      match = keys.zip(values).lazy.filter_map { |key, value| index[key][value.downcase] if value.present? }.first
      if match
        merged[id] = match
      else
        moving << id
        cleared << id if ipn.present? && !taken_ipns.add?(ipn.downcase)
      end
    end

    Part.where(id: cleared).update_all(ipn: nil)
    Part.where(id: moving).update_all(organization_id: target.id)
    merged.each { |from, to| fold_part(from, to) }

    [ moving.size, merged.size, cleared ]
  end

  # Gives +to+ everything hanging off +from+ (left empty, deleted with the
  # source organization). Stock rows are moved together with the movements
  # behind them, so each quantity still matches its ledger.
  def fold_part(from, to)
    PartStorage.where(part_id: from).find_each do |storage|
      existing = PartStorage.find_by(part_id: to, storage_location_id: storage.storage_location_id)
      if existing
        existing.update_columns(quantity: existing.quantity + storage.quantity)
        storage.delete
      else
        storage.update_columns(part_id: to)
      end
    end

    StockMovement.where(part_id: from).update_all(part_id: to)
    OrderLine.where(part_id: from).update_all(part_id: to)
    ProjectLine.where(part_id: from).update_all(part_id: to)
    repoint_links(PartTag, :part_id, from, to, :tag_id)
    PartSupplier.where(part_id: from).update_all(is_preferred: false) if PartSupplier.exists?(part_id: to, is_preferred: true)
    repoint_links(PartSupplier, :part_id, from, to, :supplier_id)
    move_attachments("Part", from, to, "images")
    move_attachments("Part", from, to, "datasheet")
    Part.where(id: from).update_all(bag_id: nil, bag_assigned_at: nil)
  end

  # New IPNs from the target's numbering for the moved parts whose IPN was
  # taken. Manual and box & bag modes have nothing to draw from: those parts
  # stay without one. Returns how many got one.
  def reassign_ipns(part_ids)
    return 0 if part_ids.empty? || %w[manual box_bag].include?(target.reload.ipn_generation_mode)

    Part.where(id: part_ids).includes(:category).find_each.count do |part|
      part.send(:assign_ipn)
      part.update_column(:ipn, part.ipn) if part.ipn.present?
    end
  end

  # -- Orders, projects, members ---------------------------------------------

  def move_with_references(model)
    taken = model.where(organization_id: target.id).where.not(reference: [ nil, "" ]).pluck(:reference).to_set(&:downcase)

    model.where(organization_id: source.id).pluck(:id, :reference).each do |id, reference|
      updates = { organization_id: target.id }
      updates[:reference] = free_code(reference, taken) { |candidate| [ candidate ] } if reference.present?
      model.where(id: id).update_all(updates)
    end
  end

  def add_members
    present = target.organization_memberships.pluck(:user_id).to_set

    source.organization_memberships.granting_access.count do |membership|
      next false unless present.add?(membership.user_id)

      target.organization_memberships.create!(
        user_id: membership.user_id,
        role: membership.owner? ? "admin" : membership.role,
        email_notifications: membership.email_notifications
      )
    end
  end
end

require "test_helper"

class OrganizationMergeTest < ActiveSupport::TestCase
  setup do
    @owner = create_user
    @target = @owner.organizations.first
    @target.update!(name: "Fablab", ipn_prefix: "FA", ipn_next_sequence: 100)
    @source = create_organization(name: "Club", ipn_prefix: "CL")
    @source.organization_memberships.create!(user: @owner, role: "owner")
  end

  def merge!
    OrganizationMerge.new(source: @source, target: @target).merge!
  end

  def stock_in(org, part, location, quantity)
    org.stock_movements.create!(part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  # Every stock row still equals the sum of the movements behind it.
  def assert_ledger_matches(part)
    part.part_storages.each do |storage|
      assert_equal part.stock_movements.where(storage_location_id: storage.storage_location_id).sum(:quantity_delta), storage.quantity
    end
  end

  test "moves the source's data into the target and deletes the source" do
    room = create_storage_location(organization: @source, name: "Atelier")
    part = create_part(organization: @source, name: "Arduino Nano", mpn: "A000005")
    stock_in(@source, part, room, 4)
    order = create_order(organization: @source, reference: "PO-1")
    order.order_lines.create!(part: part, quantity: 2)
    project = create_project(organization: @source, reference: "PRJ-1")
    project.project_lines.create!(part: part, quantity: 1)

    result = merge!

    assert_not Organization.exists?(@source.id)
    assert_equal @target.id, part.reload.organization_id
    assert_equal @target.id, room.reload.organization_id
    assert_equal @target.id, order.reload.organization_id
    assert_equal @target.id, project.reload.organization_id
    assert_equal @target.id, part.category.organization_id
    assert_equal [ @target.id ], StockMovement.where(part: part).distinct.pluck(:organization_id)
    assert_equal 4, part.part_storages.sum(:quantity)
    assert_equal "Fablab", @target.reload.name
    assert_equal 1, result.parts_moved
    assert_equal 0, result.parts_merged
  end

  test "combines categories, footprints, tags and suppliers with the same name" do
    target_category = create_category(organization: @target, name: "Resistors", code: "RES")
    source_category = create_category(organization: @source, name: "resistors", code: "R")
    child = create_category(organization: @source, name: "SMD resistors", code: "RES", parent: source_category)
    target_footprint = create_footprint(organization: @target, name: "0603")
    create_footprint(organization: @source, name: "0603")
    target_tag = create_tag(organization: @target, name: "Kit")
    create_tag(organization: @source, name: "Kit")
    target_supplier = create_supplier(organization: @target, name: "Farnell")
    create_supplier(organization: @source, name: "FARNELL")
    target_mouser = @target.suppliers.find_by!(catalog_provider: "mouser")

    part = create_part(organization: @source, category: source_category, footprint: @source.footprints.first)
    part.tags << @source.tags.first
    part.part_suppliers.create!(supplier: @source.suppliers.find_by!(name: "FARNELL"), is_preferred: true)
    part.part_suppliers.create!(supplier: @source.suppliers.find_by!(catalog_provider: "mouser"))
    order = create_order(organization: @source, supplier: @source.suppliers.find_by!(name: "FARNELL"))

    merge!
    part.reload

    assert_equal target_category, part.category
    assert_equal target_category, child.reload.parent
    assert_equal @target.id, child.organization_id
    assert_nil child.code, "a code the target already uses is cleared"
    assert_equal target_footprint, part.footprint
    assert_equal [ target_tag ], part.tags.to_a
    assert_equal [ target_mouser, target_supplier ].sort_by(&:id), part.suppliers.order(:id).to_a
    assert_equal target_supplier, order.reload.supplier
    assert_equal 1, @target.categories.where("LOWER(name) = ?", "resistors").count
    assert_equal 1, @target.suppliers.where(catalog_provider: "mouser").count
  end

  test "folds a part with the same MPN, SKU or barcode into the target's" do
    target_room = create_storage_location(organization: @target, name: "Shelf")
    target_part = create_part(organization: @target, name: "Nano", mpn: "A000005")
    stock_in(@target, target_part, target_room, 10)
    target_part.part_suppliers.create!(supplier: create_supplier(organization: @target), is_preferred: true)

    room = create_storage_location(organization: @source, name: "Drawer")
    by_mpn = create_part(organization: @source, name: "Arduino Nano", mpn: "a000005")
    by_sku = create_part(organization: @source, name: "Nano clone", sku: "NANO", mpn: "CLONE")
    target_part.update!(sku: "nano")
    stock_in(@source, by_mpn, room, 3)
    stock_in(@source, by_sku, room, 2)
    by_mpn.part_suppliers.create!(supplier: create_supplier(organization: @source), is_preferred: true)
    by_mpn.images.attach(io: file_fixture("logo.png").open, filename: "photo.png", content_type: "image/png")
    order = create_order(organization: @source)
    line = order.order_lines.create!(part: by_mpn, quantity: 5)
    project_line = create_project(organization: @source).project_lines.create!(part: by_sku, quantity: 1)
    stocktake = @source.stocktakes.create!(storage_location: room, reference: "ST-1")
    stocktake.snapshot_stock!
    stocktake.count!(stocktake.stocktake_lines.find_by!(part: by_mpn), 3, user: @owner)

    result = merge!
    target_part.reload

    assert_equal 2, result.parts_merged
    assert_not Part.exists?(by_mpn.id)
    assert_not Part.exists?(by_sku.id)
    assert_equal "Nano", target_part.name, "the target's details are kept"
    assert_equal 15, target_part.part_storages.sum(:quantity)
    assert_equal 5, target_part.part_storages.find_by!(storage_location: room).quantity
    assert_ledger_matches(target_part)
    assert_equal target_part, line.reload.part
    assert_equal target_part, project_line.reload.part
    stocktake_line = stocktake.stocktake_lines.sole
    assert_equal [ target_part.id, 5, 3 ], [ stocktake_line.part_id, stocktake_line.expected_quantity, stocktake_line.counted_quantity ]
    assert_equal 1, target_part.part_suppliers.where(is_preferred: true).count
    assert_equal 2, target_part.part_suppliers.count
    assert_equal 1, target_part.images.count
  end

  test "renames zone codes, references and IPNs the target already uses" do
    create_storage_location(organization: @target, name: "Shelf", code: "S1")
    create_part(organization: @target, ipn: "CL-00001")
    create_order(organization: @target, reference: "PO-1")
    create_project(organization: @target, reference: "PRJ-1")
    create_storage_location(organization: @target).then { |shelf| @target.stocktakes.create!(storage_location: shelf, reference: "ST-1") }

    zone = create_storage_location(organization: @source, name: "Shelf", code: "s1")
    part = create_part(organization: @source, ipn: "CL-00001")
    kept = create_part(organization: @source, ipn: "CL-00002")
    order = create_order(organization: @source, reference: "PO-1")
    project = create_project(organization: @source, reference: "PRJ-1")
    stocktake = @source.stocktakes.create!(storage_location: zone, reference: "ST-1")

    result = merge!

    assert_equal "ST-1-2", stocktake.reload.reference
    assert_equal @target.id, stocktake.organization_id
    assert_equal "s1-2", zone.reload.code
    assert_equal "PO-1-2", order.reload.reference
    assert_equal "PRJ-1-2", project.reload.reference
    assert_match(/\AFA/, part.reload.ipn, "a taken IPN is redrawn from the target's numbering")
    assert_equal "CL-00002", kept.reload.ipn
    assert_equal 1, result.codes_renamed
    assert_equal 1, result.ipns_reassigned
  end

  test "renames a box whose code is taken, with its bags and the IPN of the part holding one" do
    @target.update!(ipn_generation_mode: "box_bag")
    create_storage_location(organization: @target, name: "Box A", location_type: "box", code: "A").add_bags!(1)
    @source.update!(ipn_generation_mode: "box_bag", ipn_separator: ".")
    box = create_storage_location(organization: @source, name: "Box A", location_type: "box", code: "A")
    bag = box.add_bags!(2).first
    part = create_part(organization: @source, name: "In a bag")
    assert_equal "A.1", part.ipn

    merge!

    assert_equal "A2", box.reload.code
    assert_equal "A2-1", bag.reload.code
    assert_equal "A2-1", part.reload.ipn
    assert_equal bag, part.bag
  end

  test "brings the source's members over, owners as admins" do
    admin = create_user
    @source.organization_memberships.create!(user: admin, role: "owner")
    viewer = create_user
    @source.organization_memberships.create!(user: viewer, role: "viewer", email_notifications: false)
    invited = create_user
    @source.organization_memberships.create!(user: invited, role: "member", invitation_sent_at: Time.current)

    result = merge!

    assert_equal 2, result.members_added
    assert_equal "owner", @owner.role_in(@target)
    assert_equal "admin", admin.role_in(@target)
    assert_equal "viewer", viewer.role_in(@target)
    assert_not @target.organization_memberships.find_by!(user: viewer).email_notifications
    assert_nil invited.role_in(@target)
  end

  test "combines parameters with the same name, type and unit, and renames the others" do
    resistance = @target.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    @target.parameter_definitions.create!(name: "Gain", unit: "dB")
    source_resistance = @source.parameter_definitions.create!(name: "resistance", unit: "Ω")
    source_gain = @source.parameter_definitions.create!(name: "Gain", value_type: "text")
    source_only = @source.parameter_definitions.create!(name: "Dielectric", value_type: "text")

    target_resistors = create_category(organization: @target, name: "Resistors")
    target_resistors.update!(parameter_template: [ resistance.id ])
    source_resistors = create_category(organization: @source, name: "Resistors")
    source_resistors.update!(parameter_template: [ source_resistance.id, source_only.id ])

    kept = create_part(organization: @target, name: "Kept", mpn: "SAME")
    kept.update!(parameter_values: { resistance.id => "10k" })
    folded = create_part(organization: @source, name: "Folded", mpn: "same")
    folded.update!(parameter_values: { source_resistance.id => "22k", source_only.id => "X7R" })
    moved = create_part(organization: @source, name: "Moved")
    moved.update!(parameter_values: { source_resistance.id => "4k7", source_gain.id => "high" })

    merge!

    assert_equal [ "Dielectric", "Gain", "Gain (2)", "Resistance" ], @target.parameter_definitions.alphabetical.pluck(:name)
    assert_equal [ resistance.id, source_only.id ], target_resistors.reload.parameter_template_ids
    values = ->(part) { part.reload.part_parameters.includes(:parameter_definition).to_h { |p| [ p.name, p.value ] } }
    assert_equal({ "Resistance" => "10k", "Dielectric" => "X7R" }, values.(kept), "the target's value wins")
    assert_equal({ "Resistance" => "4k7", "Gain (2)" => "high" }, values.(moved))
    assert_not ParameterDefinition.exists?(source_resistance.id)
  end

  test "refuses to merge an organization into itself or a personal organization away" do
    assert_raises(OrganizationMerge::Error) { OrganizationMerge.new(source: @source, target: @source).merge! }
    assert_raises(OrganizationMerge::Error) { OrganizationMerge.new(source: @target, target: @source).merge! }
    assert Organization.exists?(@source.id)
  end
end

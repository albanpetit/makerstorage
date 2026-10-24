require "test_helper"

class PartMergeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @drawer = create_storage_location(organization: @org, name: "Drawer 1")
    @shelf = create_storage_location(organization: @org, name: "Shelf 2")
  end

  def stock_in(part, location, quantity)
    @org.stock_movements.create!(part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  def merge!(keep, *duplicates)
    PartMerge.new(keep: keep, duplicates: duplicates, user: @user).merge!
  end

  # Every stock row still equals the sum of the movements behind it.
  def assert_ledger_matches(part)
    part.part_storages.reload.each do |storage|
      assert_equal part.stock_movements.where(storage_location_id: storage.storage_location_id).sum(:quantity_delta), storage.quantity
    end
  end

  test "moves stock, movements, project lines and tags onto the kept part and deletes the duplicate" do
    keep = create_part(organization: @org, category: @category, name: "NE555 timer", mpn: "NE555P")
    duplicate = create_part(organization: @org, category: @category, name: "555 timer")
    stock_in(keep, @drawer, 10)
    stock_in(duplicate, @drawer, 5)
    stock_in(duplicate, @shelf, 3)
    tag = create_tag(organization: @org)
    other_tag = create_tag(organization: @org)
    keep.tags << tag
    duplicate.tags << tag << other_tag
    project = create_project(organization: @org)
    line = project.project_lines.create!(part: duplicate, quantity: 2, match_type: "mpn")

    result = merge!(keep, duplicate)

    assert_not Part.exists?(duplicate.id)
    assert_equal 18, keep.reload.total_quantity
    assert_equal 15, keep.part_storages.find_by(storage_location: @drawer).quantity
    assert_equal 3, keep.part_storages.find_by(storage_location: @shelf).quantity
    assert_equal 3, keep.stock_movements.count
    assert_ledger_matches(keep)
    assert_equal keep.id, line.reload.part_id
    assert_equal "mpn", line.match_type
    assert_equal [ tag.id, other_tag.id ].sort, keep.tag_ids.sort
    assert_equal 1, result.merged_count
    assert_equal 2, result.stock_rows
    assert_equal 2, result.movements
    assert_equal 1, result.project_lines
  end

  test "moves stocktake lines, loan lines and parameters, combining what both parts share" do
    keep = create_part(organization: @org, category: @category, name: "10k resistor", kicad_symbol: "Device:R")
    duplicate = create_part(organization: @org, category: @category, name: "10K", kicad_footprint: "Resistor_SMD:R_0603_1608Metric")
    stock_in(keep, @drawer, 10)
    stock_in(duplicate, @drawer, 5)
    stock_in(duplicate, @shelf, 4)

    stocktake = @org.stocktakes.create!(storage_location: @drawer, reference: "ST-1", user: @user)
    stocktake.snapshot_stock!
    stocktake.count!(stocktake.stocktake_lines.find_by!(part: duplicate), 5, user: @user)

    loan = @org.loans.new(borrower_name: "Ada", due_on: Date.current + 7)
    loan.loan_lines.build(part: duplicate, storage_location: @shelf, quantity: 1)
    loan.lend!(user: @user)

    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    tolerance = @org.parameter_definitions.create!(name: "Tolerance", unit: "%")
    keep.part_parameters.create!(parameter_definition: resistance, value: "10k")
    duplicate.part_parameters.create!(parameter_definition: resistance, value: "9k")
    duplicate.part_parameters.create!(parameter_definition: tolerance, value: "1%")

    merge!(keep, duplicate)

    line = stocktake.stocktake_lines.sole
    assert_equal [ keep.id, 15, 5 ], [ line.part_id, line.expected_quantity, line.counted_quantity ]
    assert_equal keep.id, loan.loan_lines.sole.reload.part_id
    assert_equal({ "Resistance" => "10k", "Tolerance" => "1%" },
                 keep.reload.part_parameters.includes(:parameter_definition).to_h { |p| [ p.parameter_definition.name, p.value ] })
    assert_equal [ "Device:R", "Resistor_SMD:R_0603_1608Metric" ], [ keep.kicad_symbol, keep.kicad_footprint ]
    assert_ledger_matches(keep)
  end

  test "keeps the kept part's details and fills its blanks from the duplicates" do
    footprint = create_footprint(organization: @org, name: "DIP-8")
    keep = create_part(organization: @org, category: @category, name: "LM358", manufacturer: "TI", min_stock_threshold: 0)
    duplicate = create_part(organization: @org, category: @category, name: "lm358 op-amp", manufacturer: "ST",
                            mpn: "LM358N", sku: "OPA-1", footprint: footprint, description: "Dual op-amp",
                            min_stock_threshold: 5)

    merge!(keep, duplicate)

    keep.reload
    assert_equal "LM358", keep.name
    assert_equal "TI", keep.manufacturer
    assert_equal "LM358N", keep.mpn
    assert_equal "OPA-1", keep.sku
    assert_equal footprint, keep.footprint
    assert_equal "Dual op-amp", keep.description
    assert_equal 5, keep.min_stock_threshold
  end

  test "takes the duplicate's IPN when the kept part has none" do
    @org.update!(ipn_generation_mode: "manual")
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category, ipn: "R-0042")

    merge!(keep, duplicate)

    assert_equal "R-0042", keep.reload.ipn
  end

  test "combines order lines on the same order and moves the others" do
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    shared = create_order(organization: @org)
    shared.order_lines.create!(part: keep, quantity: 10, unit_price: 0.5)
    dup_line = shared.order_lines.create!(part: duplicate, quantity: 4, unit_price: 0.4)
    other = create_order(organization: @org)
    moved = other.order_lines.create!(part: duplicate, quantity: 7)

    result = merge!(keep, duplicate)

    assert_equal 1, shared.order_lines.count
    combined = shared.order_lines.first
    assert_equal keep.id, combined.part_id
    assert_equal 14, combined.quantity
    assert_equal 0.5, combined.unit_price.to_f
    assert_not OrderLine.exists?(dup_line.id)
    assert_equal keep.id, moved.reload.part_id
    assert_equal 2, result.order_lines
  end

  test "keeps a zone split only when both combined lines had one" do
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    both = create_order(organization: @org)
    kept_line = both.order_lines.create!(part: keep, quantity: 10)
    kept_line.allocations.create!(storage_location: @drawer, quantity: 10)
    dup_line = both.order_lines.create!(part: duplicate, quantity: 5)
    dup_line.allocations.create!(storage_location: @drawer, quantity: 2)
    dup_line.allocations.create!(storage_location: @shelf, quantity: 3)
    one = create_order(organization: @org)
    split_line = one.order_lines.create!(part: keep, quantity: 6)
    split_line.allocations.create!(storage_location: @shelf, quantity: 6)
    one.order_lines.create!(part: duplicate, quantity: 1)

    merge!(keep, duplicate)

    line = both.order_lines.sole
    assert_equal 15, line.quantity
    assert_equal({ @drawer.id => 12, @shelf.id => 3 }, line.allocations.pluck(:storage_location_id, :quantity).to_h)
    assert line.reload.fully_allocated?
    line = one.order_lines.sole
    assert_equal 7, line.quantity
    assert_empty line.allocations
  end

  test "merges supplier links without losing the duplicate's supplier part number" do
    mouser = create_supplier(organization: @org, name: "Mouser shop")
    farnell = create_supplier(organization: @org, name: "Farnell")
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    keep_link = keep.part_suppliers.create!(supplier: mouser, is_preferred: true)
    duplicate.part_suppliers.create!(supplier: mouser, supplier_sku: "595-NE555P", unit_price: 0.3,
                                     price_breaks: [ { quantity: 100, unit_price: "0.2" } ])
    farnell_link = duplicate.part_suppliers.create!(supplier: farnell, supplier_sku: "9589899", is_preferred: false)

    merge!(keep, duplicate)

    assert_equal 2, keep.part_suppliers.count
    assert_equal "595-NE555P", keep_link.reload.supplier_sku
    assert_equal [ { "quantity" => 100, "unit_price" => "0.2" } ], keep_link.price_breaks
    assert keep_link.is_preferred
    assert_equal keep.id, farnell_link.reload.part_id
    assert_not farnell_link.is_preferred
  end

  test "the duplicate's preferred supplier becomes the kept part's when it had none" do
    supplier = create_supplier(organization: @org)
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    duplicate.part_suppliers.create!(supplier: supplier, is_preferred: true, unit_price: 1.25)

    merge!(keep, duplicate)

    assert_equal supplier, keep.reload.preferred_supplier
    assert_equal 1.25, keep.unit_price.to_f
  end

  test "moves images, and the datasheet only when the kept part has none" do
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    keep.datasheet.attach(io: StringIO.new("%PDF-1.4 keep"), filename: "keep.pdf", content_type: "application/pdf")
    duplicate.datasheet.attach(io: StringIO.new("%PDF-1.4 dup"), filename: "dup.pdf", content_type: "application/pdf")
    duplicate.images.attach(io: file_fixture("logo.png").open, filename: "photo.png", content_type: "image/png")

    merge!(keep, duplicate)

    keep.reload
    assert_equal "keep.pdf", keep.datasheet.filename.to_s
    assert_equal [ "photo.png" ], keep.images.map { |image| image.filename.to_s }
  end

  test "moves attached files, and a second datasheet joins them" do
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    keep.datasheet.attach(io: StringIO.new("%PDF-1.4 keep"), filename: "keep.pdf", content_type: "application/pdf")
    keep.attachments.attach(io: StringIO.new("notes"), filename: "notes.txt")
    duplicate.datasheet.attach(io: StringIO.new("%PDF-1.4 dup"), filename: "dup.pdf", content_type: "application/pdf")
    duplicate.attachments.attach(io: StringIO.new("ISO-10303-21;"), filename: "body.step")

    merge!(keep, duplicate)

    keep.reload
    assert_equal "keep.pdf", keep.datasheet.filename.to_s
    assert_equal %w[body.step dup.pdf notes.txt], keep.attachments.map { |file| file.filename.to_s }.sort
    assert_equal "%PDF-1.4 dup", keep.attachments.find { |file| file.filename.to_s == "dup.pdf" }.download
  end

  test "merges several duplicates at once" do
    keep = create_part(organization: @org, category: @category)
    first = create_part(organization: @org, category: @category)
    second = create_part(organization: @org, category: @category)
    stock_in(first, @drawer, 2)
    stock_in(second, @drawer, 3)

    result = merge!(keep, first, second)

    assert_equal 2, result.merged_count
    assert_equal 5, keep.reload.total_quantity
    assert_not Part.exists?(id: [ first.id, second.id ])
    assert_ledger_matches(keep)
  end

  test "refuses parts counted in different units, another organization's part, and nothing to merge" do
    keep = create_part(organization: @org, category: @category, unit: "piece")
    wire = create_part(organization: @org, category: @category, unit: "meter")
    other_org = create_organization
    foreign = create_part(organization: other_org, category: create_category(organization: other_org))

    assert_raises(PartMerge::Error) { merge!(keep, wire) }
    assert_raises(PartMerge::Error) { merge!(keep, foreign) }
    assert_raises(PartMerge::Error) { merge!(keep, keep) }
    assert Part.exists?(wire.id)
    assert Part.exists?(foreign.id)
  end

  test "drops the duplicate's 'not duplicates' marks" do
    keep = create_part(organization: @org, category: @category)
    duplicate = create_part(organization: @org, category: @category)
    third = create_part(organization: @org, category: @category)
    PartDuplicateDismissal.dismiss!([ duplicate, third ])

    merge!(keep, duplicate)

    assert_equal 0, PartDuplicateDismissal.count
  end

  test "box & bag: the kept part takes the duplicate's bag when it has none" do
    @org.update!(ipn_generation_mode: "box_bag")
    box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    bag = box.add_bags!(1).first
    keep = create_part(organization: @org, category: @category, skip_bag_claim: true)
    duplicate = create_part(organization: @org, category: @category, bag: bag)
    stock_in(duplicate, bag, 4)

    merge!(keep, duplicate)

    keep.reload
    assert_equal bag, keep.bag
    assert_equal "A-1", keep.ipn
    assert_equal 4, keep.part_storages.find_by(storage_location: bag).quantity
  end

  test "box & bag: stock in the duplicate's bag moves into the kept part's bag" do
    @org.update!(ipn_generation_mode: "box_bag")
    box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    bag, other_bag = box.add_bags!(2)
    keep = create_part(organization: @org, category: @category, bag: bag)
    duplicate = create_part(organization: @org, category: @category, bag: other_bag)
    stock_in(keep, bag, 1)
    stock_in(duplicate, other_bag, 6)

    merge!(keep, duplicate)

    keep.reload
    assert_equal bag, keep.bag
    assert_equal "A-1", keep.ipn
    assert_equal 7, keep.part_storages.find_by(storage_location: bag).quantity
    assert_equal 0, keep.part_storages.find_by(storage_location: other_bag).quantity
    assert_nil other_bag.reload.bag_occupant
    assert_ledger_matches(keep)
    assert_equal 2, keep.stock_movements.where("reason LIKE ?", "Merged duplicate%").where(transfer: true).count
  end
end

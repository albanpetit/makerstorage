require "test_helper"

class PartTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @category = create_category(organization: @org)
  end

  test "valid with organization, category, and name" do
    part = Part.new(organization: @org, category: @category, name: "Resistor 10k")
    assert part.valid?
  end

  test "defaults unit to piece" do
    part = create_part(organization: @org, category: @category)
    assert_equal "piece", part.unit
  end

  test "rejects a unit outside the allowed list" do
    part = Part.new(organization: @org, category: @category, name: "X", unit: "kilogram")
    assert_not part.valid?
    assert_includes part.errors[:unit], "is not included in the list"
  end

  test "accepts every declared unit" do
    Part::UNITS.each do |unit|
      part = Part.new(organization: @org, category: @category, name: "Widget", unit: unit)
      assert part.valid?, "expected unit #{unit} to be valid"
    end
  end

  test "image_source_url only accepts https images from a supplier image host" do
    part = Part.new(organization: @org, category: @category, name: "Widget")

    part.image_source_url = ""
    assert part.valid?, "blank image_source_url should be allowed"

    [ "https://www.mouser.com/img.png", "https://mm.digikey.com/Volume0/x.jpg", "https://digikey.com/x.jpg" ].each do |url|
      part.image_source_url = url
      assert part.valid?, "#{url} should be allowed"
    end

    [ "javascript:alert(1)", "http://www.mouser.com/img.png", "https://evil.example/img.png",
      "https://mouser.com.evil.example/img.png", "https://notmouser.com/img.png" ].each do |url|
      part.image_source_url = url
      assert_not part.valid?, "#{url} should be refused"
      assert part.errors[:image_source_url].any? { |message| message.start_with?("must be an https image from a supplier catalog") }
    end
  end

  test "a part saved with an image from another host stays editable, but its image is not shown" do
    part = create_part(organization: @org, category: @category, name: "Legacy")
    part.update_column(:image_source_url, "https://evil.example/img.png")

    part.reload.name = "Legacy renamed"
    assert part.valid?, "an unchanged legacy image_source_url must not block other edits"
    assert_nil part.hotlinked_image_url
  end

  test "supplier_image_url keeps supplier hosts, upgrades http and drops everything else" do
    assert_equal "https://www.mouser.com/images/x.jpg?v=1", Part.supplier_image_url("http://www.mouser.com/images/x.jpg?v=1")
    assert_equal "https://mm.digikey.com/a.jpg", Part.supplier_image_url("https://MM.DigiKey.com/a.jpg")
    assert_equal "https://assets.lcsc.com/images/lcsc/900x900/a.jpg", Part.supplier_image_url("https://assets.lcsc.com/images/lcsc/900x900/a.jpg")
    assert_nil Part.supplier_image_url("https://evilmouser.com/a.jpg")
    assert_nil Part.supplier_image_url("https://user:pass@www.mouser.com/a.jpg")
    assert_nil Part.supplier_image_url("ftp://www.mouser.com/a.jpg")
    assert_nil Part.supplier_image_url("not a url")
    assert_nil Part.supplier_image_url(nil)
  end

  test "category must belong to the same organization" do
    other_org = create_organization
    other_category = create_category(organization: other_org)
    part = Part.new(organization: @org, category: other_category, name: "X")
    assert_not part.valid?
    assert_includes part.errors[:category], "must belong to the same organization"
  end

  test "total_quantity sums part_storages across locations" do
    part = create_part(organization: @org, category: @category)
    loc_a = create_storage_location(organization: @org, name: "A")
    loc_b = create_storage_location(organization: @org, name: "B")
    PartStorage.create!(part: part, storage_location: loc_a, quantity: 30)
    PartStorage.create!(part: part, storage_location: loc_b, quantity: 12)

    assert_equal 42, part.total_quantity
  end

  test "total_quantity is zero with no stock" do
    part = create_part(organization: @org, category: @category)
    assert_equal 0, part.total_quantity
  end

  test "reference prefers mpn, then sku, then falls back to name" do
    part = create_part(organization: @org, category: @category, name: "Resistor 10k", mpn: "RC0805", sku: "RES-10K")
    assert_equal "RC0805", part.reference

    part.mpn = nil
    assert_equal "RES-10K", part.reference

    part.sku = nil
    assert_equal "Resistor 10k", part.reference
  end

  test "low_stock? and out_of_stock?" do
    part = create_part(organization: @org, category: @category, min_stock_threshold: 50)
    location = create_storage_location(organization: @org)

    assert part.out_of_stock?
    assert part.low_stock?

    PartStorage.create!(part: part, storage_location: location, quantity: 20)
    part.reload
    assert_not part.out_of_stock?
    assert part.low_stock?

    PartStorage.find_by(part: part, storage_location: location).update!(quantity: 100)
    part.reload
    assert_not part.low_stock?
  end

  test "stock_status reflects thresholds" do
    part = create_part(organization: @org, category: @category, min_stock_threshold: 10)
    location = create_storage_location(organization: @org)

    assert_equal :out_of_stock, part.stock_status

    PartStorage.create!(part: part, storage_location: location, quantity: 5)
    part.reload
    assert_equal :low_stock, part.stock_status

    PartStorage.find_by(part: part, storage_location: location).update!(quantity: 50)
    part.reload
    assert_equal :sufficient, part.stock_status
  end

  test "search matches across name, mpn, sku, manufacturer, value, and barcode, case-insensitively" do
    resistor = create_part(organization: @org, category: @category, name: "Resistor 10k", mpn: "RES-10K-0603")
    capacitor = create_part(organization: @org, category: @category, name: "Capacitor 100nF", mpn: "CAP-100N")

    assert_includes Part.search("resistor"), resistor
    assert_not_includes Part.search("resistor"), capacitor
    assert_includes Part.search("RES-10K"), resistor
    assert_includes Part.search("100nf"), capacitor
  end

  test "search returns nothing for a query matching no fields" do
    create_part(organization: @org, category: @category, name: "Resistor 10k")
    assert_empty Part.search("nonexistent-query-xyz")
  end

  # IPN generation

  test "assigns an incremental ipn on create and advances the org counter" do
    org = create_organization(ipn_generation_mode: "incremental", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 1)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category)
    assert_equal "MS-00001", part.ipn
    assert_equal 2, org.reload.ipn_next_sequence

    second = create_part(organization: org, category: category)
    assert_equal "MS-00002", second.ipn
    assert_equal 3, org.reload.ipn_next_sequence
  end

  test "ipn includes the category code when enabled" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: true, ipn_separator: "-", ipn_digits: 4, ipn_next_sequence: 7)
    category = create_category(organization: org, code: "RES")

    part = create_part(organization: org, category: category)
    assert_equal "MS-RES-0007", part.ipn
  end

  test "does not auto-generate an ipn in manual mode" do
    org = create_organization(ipn_generation_mode: "manual", ipn_next_sequence: 12)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category)
    assert_nil part.ipn
    assert_equal 12, org.reload.ipn_next_sequence, "counter must not advance without a generated ipn"
  end

  test "keeps an explicitly supplied ipn and leaves the counter untouched" do
    org = create_organization(ipn_generation_mode: "incremental", ipn_next_sequence: 5)
    category = create_category(organization: org)

    part = create_part(organization: org, category: category, ipn: "CUSTOM-1")
    assert_equal "CUSTOM-1", part.ipn
    assert_equal 5, org.reload.ipn_next_sequence
  end

  test "ipn is unique per organization" do
    create_part(organization: @org, category: @category, ipn: "MS-0001")
    duplicate = Part.new(organization: @org, category: @category, name: "Dupe", ipn: "MS-0001")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ipn], "has already been taken"
  end

  test "skips a taken reference by redrawing from the next seed" do
    org = create_organization(ipn_generation_mode: "random", ipn_charset: "numeric", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 6, ipn_next_sequence: 5)
    category = create_category(organization: org)

    # Occupy the reference the counter would draw first, forcing a redraw.
    taken = org.next_ipn(sequence: 5)
    create_part(organization: org, category: category, ipn: taken)

    part = create_part(organization: org, category: category)
    assert_equal org.next_ipn(sequence: 6), part.ipn
    assert_not_equal taken, part.ipn
    assert_equal 7, org.reload.ipn_next_sequence
  end

  test "the same ipn may exist in different organizations" do
    create_part(organization: @org, category: @category, ipn: "MS-0001")

    other_org = create_organization
    other_part = Part.new(organization: other_org, category: create_category(organization: other_org), name: "Elsewhere", ipn: "MS-0001")
    assert other_part.valid?
  end

  test "barcode is unique per organization" do
    create_part(organization: @org, category: @category, barcode: "123456789012")
    duplicate = Part.new(organization: @org, category: @category, name: "Dupe", barcode: "123456789012")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:barcode], "has already been taken"
  end

  test "the same barcode may exist in different organizations" do
    create_part(organization: @org, category: @category, barcode: "123456789012")

    other_org = create_organization
    other_part = Part.new(organization: other_org, category: create_category(organization: other_org), name: "Elsewhere", barcode: "123456789012")
    assert other_part.valid?
  end

  test "destroy un-matches the part from project BOM lines instead of crashing" do
    org = create_organization
    part = create_part(organization: org)
    line = create_project(organization: org).project_lines.create!(part: part, quantity: 2, match_type: "mpn")

    assert part.destroy
    line.reload
    assert_nil line.part_id
    assert_equal "none", line.match_type
  end

  test "destroy keeps BOM matches when the part is blocked by stock history" do
    org = create_organization
    part = create_part(organization: org)
    location = create_storage_location(organization: org)
    org.stock_movements.create!(part: part, storage_location: location, movement_type: "in", quantity_delta: 1)
    line = create_project(organization: org).project_lines.create!(part: part, quantity: 2, match_type: "mpn")

    assert_not part.destroy
    assert_equal part.id, line.reload.part_id
  end

  test "stock scopes judge a never-stocked part as holding zero" do
    org = create_organization
    location = create_storage_location(organization: org)
    never_stocked = create_part(organization: org, min_stock_threshold: 10)
    no_threshold = create_part(organization: org, min_stock_threshold: 0)
    stocked = create_part(organization: org, min_stock_threshold: 10)
    org.stock_movements.create!(part: stocked, storage_location: location, movement_type: "in", quantity_delta: 20)

    assert_equal [ never_stocked ], org.parts.low_stock.to_a
    assert_equal [ no_threshold, stocked ].sort_by(&:id), org.parts.sufficient_stock.to_a.sort_by(&:id)
    assert_equal 1, org.low_stock_parts_count
  end

  test "fallback_storage_location is the first zone the part was stocked in" do
    part = create_part(organization: @org, category: @category)
    assert_nil part.fallback_storage_location

    later_zone = create_storage_location(organization: @org)
    first_zone = create_storage_location(organization: @org)
    part.part_storages.create!(storage_location: first_zone, quantity: 0)
    part.part_storages.create!(storage_location: later_zone, quantity: 5)

    assert_equal first_zone, part.reload.fallback_storage_location
    assert_equal first_zone, Part.includes(part_storages: :storage_location).find(part.id).fallback_storage_location
  end

  test "images must be web images under 10 MB" do
    part = create_part(organization: create_organization)

    part.images.attach(io: StringIO.new("<html></html>"), filename: "x.html", content_type: "text/html", identify: false)
    assert_not part.valid?
    assert_match(/must be a PNG, JPEG, GIF or WEBP file/, part.errors[:images].join)

    part.images.detach
    part.images.attach(io: StringIO.new("a" * (10.megabytes + 1)), filename: "big.png", content_type: "image/png", identify: false)
    assert_not part.valid?
    assert_match(/smaller than 10 MB/, part.errors[:images].join)

    part.images.detach
    part.images.attach(io: File.open(Rails.root.join("test/fixtures/files/logo.png")), filename: "logo.png", content_type: "image/png")
    assert part.valid?
  end

  test "attachments take any type of file, up to a size and a count" do
    part = create_part(organization: @org)
    part.attachments.attach(io: StringIO.new("<html></html>"), filename: "page.html")
    part.attachments.attach(io: StringIO.new("ISO-10303-21;"), filename: "body.step")
    assert part.valid?, part.errors.full_messages.to_sentence

    part.attachments.attach(io: StringIO.new("x"), filename: "big.bin")
    part.attachments.blobs.find { |blob| blob.filename.to_s == "big.bin" }.update_column(:byte_size, 50.megabytes + 1)
    assert_not part.reload.valid?
    assert_match(/must be smaller than 50 MB/, part.errors[:attachments].join)
  end

  test "a part holds at most MAX_ATTACHMENTS files" do
    part = create_part(organization: @org)
    files = Array.new(Part::MAX_ATTACHMENTS + 1) { |i| { io: StringIO.new("f#{i}"), filename: "f#{i}.txt" } }
    assert_not part.attachments.attach(files)
    assert_includes part.errors[:attachments].join, "can't be more than #{Part::MAX_ATTACHMENTS} files"

    assert part.reload.update(name: "Renamed part"), "other saves don't count the files"
  end

  test "a datasheet must be a pdf" do
    part = create_part(organization: create_organization)
    part.datasheet.attach(io: StringIO.new("not a pdf"), filename: "ds.txt", content_type: "text/plain", identify: false)

    assert_not part.valid?
    assert_match(/must be a PDF file/, part.errors[:datasheet].join)
  end

  test "order_unit_price applies the supplier's price break for the quantity" do
    org = create_organization
    part = create_part(organization: org, unit_price: 1)
    supplier = create_supplier(organization: org)
    part.part_suppliers.create!(supplier: supplier, unit_price: 0.2, price_breaks: [ { quantity: 100, unit_price: "0.1" } ])

    assert_equal 0.2, part.order_unit_price(supplier.id).to_f
    assert_equal 0.2, part.order_unit_price(supplier.id, 10).to_f
    assert_equal 0.1, part.order_unit_price(supplier.id, 100).to_f
  end

  test "purchase_price_lines lists priced lines of orders not cancelled, oldest order first" do
    org = create_organization
    part = create_part(organization: org)
    supplier = create_supplier(organization: org)
    late = create_order(organization: org, supplier: supplier, reference: "PO-LATE", ordered_at: Date.new(2026, 5, 1))
    early = create_order(organization: org, supplier: supplier, reference: "PO-EARLY", ordered_at: Date.new(2026, 1, 1))
    cancelled = create_order(organization: org, supplier: supplier, reference: "PO-CANCELLED", ordered_at: Date.new(2026, 3, 1), status: "cancelled")
    unpriced = create_order(organization: org, supplier: supplier, reference: "PO-UNPRICED", ordered_at: Date.new(2026, 2, 1))
    late.order_lines.create!(part: part, quantity: 10, unit_price: 0.5)
    early.order_lines.create!(part: part, quantity: 10, unit_price: 0.7)
    cancelled.order_lines.create!(part: part, quantity: 10, unit_price: 0.1)
    unpriced.order_lines.create!(part: part, quantity: 10)

    assert_equal %w[PO-EARLY PO-LATE], part.purchase_price_lines.map { |line| line.order.reference }
    assert_equal %w[PO-LATE PO-EARLY], part.purchase_price_lines(:desc).map { |line| line.order.reference }
  end
end

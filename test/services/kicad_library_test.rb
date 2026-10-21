require "test_helper"

class KicadLibraryTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @passives = create_category(organization: @org, name: "Passives")
    @resistors = create_category(organization: @org, name: "Resistors", parent: @passives)
    @library = KicadLibrary.new(@org, base_url: "https://inventory.example")
  end

  test "a part's own symbol wins over its category's" do
    @resistors.update!(kicad_symbol: "Device:R_Small")
    part = create_part(organization: @org, category: @resistors, kicad_symbol: "Custom:R_Special")

    assert_equal "Custom:R_Special", @library.symbol_for(part)
  end

  test "a part without a symbol takes its category's, then the nearest ancestor's" do
    @passives.update!(kicad_symbol: "Device:R_US")
    part = create_part(organization: @org, category: @resistors)
    assert_equal "Device:R_US", library.symbol_for(part)

    @resistors.update!(kicad_symbol: "Device:R_Small")
    assert_equal "Device:R_Small", library.symbol_for(part)
  end

  test "with no symbol set, one is guessed from the category names" do
    smd = create_category(organization: @org, name: "SMD", parent: @resistors)
    electrolytic = create_category(organization: @org, name: "Electrolytic Capacitors")
    leds = create_category(organization: @org, name: "LEDs")
    ics = create_category(organization: @org, name: "Integrated Circuits")

    assert_equal "Device:R", library.symbol_for(create_part(organization: @org, category: smd))
    assert_equal "Device:C_Polarized", library.symbol_for(create_part(organization: @org, category: electrolytic))
    assert_equal "Device:LED", library.symbol_for(create_part(organization: @org, category: leds))
    assert_nil library.symbol_for(create_part(organization: @org, category: ics))
  end

  test "categories list only those holding parts KiCad can place, by full path" do
    create_part(organization: @org, category: @resistors)
    create_part(organization: @org, category: create_category(organization: @org, name: "Microcontrollers"))
    create_part(organization: @org, category: create_category(organization: @org, name: "Capacitors"), status: "obsolete")

    rows = @library.categories
    assert_equal [ { id: @resistors.id.to_s, name: "Passives > Resistors", description: "1 part" } ], rows
  end

  test "category parts carry the stock in their description and leave other categories out" do
    zone = create_storage_location(organization: @org)
    part = create_part(organization: @org, category: @resistors, name: "10k 0603", description: "Thick film")
    StockMovement.create!(organization: @org, part: part, storage_location: zone, movement_type: "in", quantity_delta: 250)
    create_part(organization: @org, category: @passives, kicad_symbol: "Device:C")

    rows = @library.category_parts(@resistors.id)
    assert_equal [ { id: part.id.to_s, name: "10k 0603", description: "Stock: 250 · Thick film" } ], rows
  end

  test "category parts of another organization's category is nil" do
    other = create_organization
    foreign = create_category(organization: other, name: "Resistors")
    create_part(organization: other, category: foreign)

    assert_nil @library.category_parts(foreign.id)
  end

  test "parts sharing a name get their IPN appended, and colons are replaced" do
    first = create_part(organization: @org, category: @resistors, name: "R:10k", ipn: "MS-1")
    second = create_part(organization: @org, category: @resistors, name: "r:10K")
    second.update_column(:ipn, nil)

    names = @library.category_parts(@resistors.id).to_h { |row| [ row[:id], row[:name] ] }
    assert_equal "R-10k (MS-1)", names[first.id.to_s]
    assert_equal "r-10K (##{second.id})", names[second.id.to_s]
  end

  test "part returns the symbol and MakerStorage's fields as KiCad strings" do
    footprint = create_footprint(organization: @org, name: "0603", kicad_footprint: "Resistor_SMD:R_0603_1608Metric")
    supplier = create_supplier(organization: @org, name: "LCSC")
    part = create_part(organization: @org, category: @resistors, footprint: footprint, name: "10k 0603",
      value: "10k", mpn: "RC0603FR-0710KL", manufacturer: "Yageo", description: "Thick film 1%", ipn: "MS-00042")
    part.part_suppliers.create!(supplier: supplier, supplier_sku: "C25804", is_preferred: true)
    part.tags << create_tag(organization: @org, name: "Popular")

    result = @library.part(part.id)
    assert_equal part.id.to_s, result[:id]
    assert_equal "10k 0603", result[:name]
    assert_equal "Device:R", result[:symbolIdStr]
    assert_equal "False", result[:exclude_from_bom]

    fields = result[:fields]
    assert_equal({ value: "10k", visible: "True" }, fields["value"])
    assert_equal({ value: "Resistor_SMD:R_0603_1608Metric", visible: "False" }, fields["footprint"])
    assert_equal "Thick film 1%", fields["description"][:value]
    assert_equal "Popular", fields["keywords"][:value]
    assert_equal "Yageo", fields["Manufacturer"][:value]
    assert_equal "RC0603FR-0710KL", fields["MPN"][:value]
    assert_equal "MS-00042", fields["IPN"][:value]
    assert_equal "LCSC", fields["Supplier"][:value]
    assert_equal "C25804", fields["Supplier SKU"][:value]
    assert_equal "https://inventory.example/parts/#{part.id}", fields["MakerStorage"][:value]
    assert_not fields.key?("datasheet"), "blank fields are left out"
  end

  test "part links an attached datasheet and prefers the part's own footprint" do
    footprint = create_footprint(organization: @org, kicad_footprint: "Resistor_SMD:R_0603_1608Metric")
    part = create_part(organization: @org, category: @resistors, footprint: footprint, kicad_footprint: "Resistor_SMD:R_0402_1005Metric")
    part.datasheet.attach(io: StringIO.new("%PDF-1.4 test"), filename: "ds.pdf", content_type: "application/pdf")

    fields = @library.part(part.id)[:fields]
    assert_equal "Resistor_SMD:R_0402_1005Metric", fields["footprint"][:value]
    assert_match %r{\Ahttps://inventory\.example/files/.+/ds\.pdf\z}, fields["datasheet"][:value]
    assert_equal part.name, fields["value"][:value], "the name stands in for a missing value"
  end

  test "part is nil for an obsolete part, a part without symbol, or another organization's part" do
    obsolete = create_part(organization: @org, category: @resistors, status: "obsolete")
    unmapped = create_part(organization: @org, category: create_category(organization: @org, name: "Modules"))
    foreign = create_part(organization: create_organization, kicad_symbol: "Device:R")

    assert_nil @library.part(obsolete.id)
    assert_nil @library.part(unmapped.id)
    assert_nil @library.part(foreign.id)
  end

  test "coverage counts parts with and without a symbol, obsolete ones aside" do
    create_part(organization: @org, category: @resistors)
    create_part(organization: @org, category: create_category(organization: @org, name: "Modules"))
    create_part(organization: @org, category: @resistors, status: "obsolete")

    assert_equal({ listed: 1, without_symbol: 1 }, @library.coverage)
  end

  test "a token authenticates its organization until it is replaced or revoked" do
    token = KicadLibrary.issue_token!(@org)
    assert token.start_with?(KicadLibrary::TOKEN_PREFIX)
    assert_equal KicadLibrary.digest(token), @org.reload.kicad_token_digest
    assert_not_includes @org.attributes.values, token

    assert_equal @org, KicadLibrary.authenticate(token)
    assert_not_nil @org.reload.kicad_token_last_used_at
    assert_nil KicadLibrary.authenticate("mskicad_wrong")
    assert_nil KicadLibrary.authenticate(nil)

    replacement = KicadLibrary.issue_token!(@org)
    assert_nil KicadLibrary.authenticate(token)
    assert_equal @org, KicadLibrary.authenticate(replacement)

    KicadLibrary.revoke_token!(@org)
    assert_nil KicadLibrary.authenticate(replacement)
    assert_nil @org.reload.kicad_token_created_at
  end

  test "the library file points KiCad at the root URL with the token" do
    file = JSON.parse(KicadLibrary.library_file(@org, token: "mskicad_abc", root_url: "https://inventory.example/kicad/"))

    assert_equal "REST_API", file.dig("source", "type")
    assert_equal "v1", file.dig("source", "api_version")
    assert_equal "https://inventory.example/kicad/", file.dig("source", "root_url")
    assert_equal "mskicad_abc", file.dig("source", "token")
    assert_includes file["name"], @org.name
  end

  private

  # A fresh instance: categories are cached per instance.
  def library
    KicadLibrary.new(@org, base_url: "https://inventory.example")
  end
end

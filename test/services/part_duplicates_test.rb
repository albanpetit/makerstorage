require "test_helper"

class PartDuplicatesTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @category = create_category(organization: @org)
  end

  def groups
    PartDuplicates.new(@org.reload).groups
  end

  test "pairs parts whose part numbers match once case, spaces and punctuation are ignored" do
    a = create_part(organization: @org, category: @category, name: "Resistor A", mpn: "RC0603FR-0710KL")
    b = create_part(organization: @org, category: @category, name: "Resistor B", sku: "rc0603fr 0710kl")
    create_part(organization: @org, category: @category, name: "Something else", mpn: "NE555P")

    group = groups.sole
    assert_equal [ a.id, b.id ], group.part_ids
    assert group.certain
    assert_equal [ "Same part number “RC0603FR-0710KL”" ], group.reasons
  end

  test "pairs a part number with another part's supplier part number or barcode" do
    supplier = create_supplier(organization: @org)
    a = create_part(organization: @org, category: @category, mpn: "C25804")
    b = create_part(organization: @org, category: @category)
    b.part_suppliers.create!(supplier: supplier, supplier_sku: "C25804")
    c = create_part(organization: @org, category: @category, barcode: "c-25804")

    assert_equal [ [ a.id, b.id, c.id ] ], groups.map(&:part_ids)
  end

  test "possible duplicates: same name, value and footprint, or same category, value and footprint" do
    footprint = create_footprint(organization: @org, name: "0603")
    a = create_part(organization: @org, category: @category, name: "10k resistor", value: "10k", footprint: footprint)
    b = create_part(organization: @org, category: @category, name: "10K  Resistor", value: "10K", footprint: footprint)
    c = create_part(organization: @org, category: @category, name: "Résistance 10 kΩ", value: "10 k", footprint: footprint)
    create_part(organization: @org, category: @category, name: "10k resistor", value: "10k")
    create_part(organization: @org, category: create_category(organization: @org), name: "Other", value: "10k", footprint: footprint)

    group = groups.sole
    assert_equal [ a.id, b.id, c.id ], group.part_ids
    assert_not group.certain
    assert_equal [ "Same name, value and footprint", "Same category, value and footprint" ], group.reasons
  end

  test "ignores short part numbers and parts of other organizations" do
    create_part(organization: @org, category: @category, mpn: "A1")
    create_part(organization: @org, category: @category, sku: "a-1")
    other = create_organization
    create_part(organization: other, category: create_category(organization: other), mpn: "NE555P")
    create_part(organization: @org, category: @category, mpn: "NE555P")

    assert_empty groups
  end

  test "dismissed pairs are not grouped again, until a new part matches" do
    a = create_part(organization: @org, category: @category, mpn: "NE555P")
    b = create_part(organization: @org, category: @category, sku: "NE-555-P")
    PartDuplicateDismissal.dismiss!([ b, a ])

    assert_empty groups

    c = create_part(organization: @org, category: @category, barcode: "ne555p")
    assert_equal [ [ a.id, b.id, c.id ] ], groups.map(&:part_ids)
  end

  test "certain groups come first" do
    footprint = create_footprint(organization: @org)
    create_part(organization: @org, category: @category, name: "Aaa", value: "1", footprint: footprint)
    create_part(organization: @org, category: @category, name: "Aab", value: "1", footprint: footprint)
    create_part(organization: @org, category: @category, name: "Zzz", mpn: "XYZ123")
    create_part(organization: @org, category: @category, name: "Zzy", sku: "xyz123")

    assert_equal [ true, false ], groups.map(&:certain)
  end
end

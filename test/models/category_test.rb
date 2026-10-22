require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
  end

  test "valid with organization and name" do
    category = Category.new(organization: @org, name: "Resistors")
    assert category.valid?
  end

  test "a KiCad symbol must read Library:Symbol, blanks stored as nil" do
    category = Category.new(organization: @org, name: "Resistors", kicad_symbol: "  ")
    assert category.valid?
    assert_nil category.kicad_symbol

    %w[Device:R Connector_Generic:Conn_01x02].each do |symbol|
      category.kicad_symbol = symbol
      assert category.valid?, symbol
    end
    [ "R", "Device:", ":R", "Device:R:extra", " :R" ].each do |symbol|
      category.kicad_symbol = symbol
      assert_not category.valid?, symbol
    end
  end

  test "requires a unique name within the organization" do
    create_category(organization: @org, name: "Resistors")
    dup = Category.new(organization: @org, name: "Resistors")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "the database rejects a duplicate name that skips validation (concurrent creation)" do
    create_category(organization: @org, name: "Resistors")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Category.new(organization: @org, name: "Resistors").save!(validate: false)
    end
  end

  test "requires a unique name regardless of case" do
    create_category(organization: @org, name: "Resistors")
    dup = Category.new(organization: @org, name: "resistors")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "the database rejects a name differing only in case" do
    create_category(organization: @org, name: "Resistors")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Category.new(organization: @org, name: "RESISTORS").save!(validate: false)
    end
  end

  test "allows the same name in a different organization" do
    create_category(organization: @org, name: "Resistors")
    other_org = create_organization
    dup = Category.new(organization: other_org, name: "Resistors")
    assert dup.valid?
  end

  test "requires a unique code within the organization, case-insensitively" do
    create_category(organization: @org, name: "Resistors", code: "RES")
    dup = Category.new(organization: @org, name: "Resistors 2", code: "res")
    assert_not dup.valid?
    assert_includes dup.errors[:code], "has already been taken"
  end

  test "code is optional" do
    category = Category.new(organization: @org, name: "Resistors")
    assert category.valid?
  end

  test "cannot be its own parent" do
    category = create_category(organization: @org)
    category.parent_id = category.id
    assert_not category.valid?
    assert_includes category.errors[:parent_id], "cannot be itself"
  end

  test "validation errors are translated" do
    category = create_category(organization: @org)
    category.parent_id = category.id

    I18n.with_locale(:fr) do
      assert_not category.valid?
      assert_includes category.errors.full_messages, "Parent ne peut pas être elle-même"
    end
  end

  test "parent must belong to the same organization" do
    other_org = create_organization
    parent = create_category(organization: other_org)
    child = Category.new(organization: @org, name: "Child", parent: parent)
    assert_not child.valid?
    assert_includes child.errors[:parent], "must belong to the same organization"
  end

  test "parent cannot be a descendant of the category" do
    grandparent = create_category(organization: @org, name: "Passives")
    parent = create_category(organization: @org, name: "Resistors", parent: grandparent)
    child = create_category(organization: @org, name: "SMD", parent: parent)

    grandparent.parent = child
    assert_not grandparent.valid?
    assert_includes grandparent.errors[:parent], "cannot be a descendant of this category"
  end

  test "root? and has_children?" do
    parent = create_category(organization: @org)
    child = create_category(organization: @org, parent: parent)

    assert parent.root?
    assert parent.has_children?
    assert_not child.root?
    assert_not child.has_children?
  end

  test "path_names lists names from the root down" do
    root = create_category(organization: @org, name: "Passives")
    child = create_category(organization: @org, name: "Resistors", parent: root)

    assert_equal [ "Passives", "Resistors" ], child.path_names
    assert_equal [ "Passives" ], root.path_names
  end

  test "full_path builds the breadcrumb from ancestors" do
    grandparent = create_category(organization: @org, name: "Passives")
    parent = create_category(organization: @org, name: "Resistors", parent: grandparent)
    child = create_category(organization: @org, name: "SMD", parent: parent)

    assert_equal "Passives > Resistors > SMD", child.full_path
  end

  test "ancestors and descendants" do
    grandparent = create_category(organization: @org, name: "Passives")
    parent = create_category(organization: @org, name: "Resistors", parent: grandparent)
    child = create_category(organization: @org, name: "SMD", parent: parent)

    assert_equal [ parent, grandparent ], child.ancestors
    assert_equal [ parent, child ], grandparent.descendants
  end

  test "self_and_descendant_ids covers the whole subtree" do
    grandparent = create_category(organization: @org, name: "Passives")
    parent = create_category(organization: @org, name: "Resistors", parent: grandparent)
    child = create_category(organization: @org, name: "SMD", parent: parent)

    assert_equal [ grandparent.id, parent.id, child.id ].sort, grandparent.self_and_descendant_ids.sort
    assert_equal [ child.id ], child.self_and_descendant_ids
  end

  test "a category's parameter template inherits its parents', root first, each parameter once" do
    org = create_organization
    resistance = org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    tolerance = org.parameter_definitions.create!(name: "Tolerance", unit: "%")
    power = org.parameter_definitions.create!(name: "Power rating", unit: "W")
    passives = create_category(organization: org, name: "Passives")
    resistors = create_category(organization: org, name: "Resistors", parent: passives)
    smd = create_category(organization: org, name: "SMD", parent: resistors)

    passives.update!(parameter_template: [ tolerance.id ])
    resistors.update!(parameter_template: [ resistance.id, power.id, tolerance.id ])

    assert_equal [ tolerance.id ], passives.parameter_template_ids
    assert_equal [ tolerance.id, resistance.id, power.id ], smd.parameter_template_ids

    resistors.update!(parameter_template: [ power.id ])
    assert_equal [ power.id ], resistors.category_parameters.reload.map(&:parameter_definition_id)
    assert_equal [ tolerance.id, power.id ], Category.parameter_templates(org)[smd.id]
  end

  test "a category template only takes its own organization's parameters" do
    category = create_category(organization: create_organization)
    foreign = create_organization.parameter_definitions.create!(name: "Gain", unit: "dB")

    category.parameter_template = [ foreign.id ]
    assert_not category.save
  end
end

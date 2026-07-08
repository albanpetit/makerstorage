require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
  end

  test "valid with organization and name" do
    category = Category.new(organization: @org, name: "Resistors")
    assert category.valid?
  end

  test "requires a unique name within the organization" do
    create_category(organization: @org, name: "Resistors")
    dup = Category.new(organization: @org, name: "Resistors")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
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

  test "parent must belong to the same organization" do
    other_org = create_organization
    parent = create_category(organization: other_org)
    child = Category.new(organization: @org, name: "Child", parent: parent)
    assert_not child.valid?
    assert_includes child.errors[:parent], "must belong to the same organization"
  end

  test "root? and has_children?" do
    parent = create_category(organization: @org)
    child = create_category(organization: @org, parent: parent)

    assert parent.root?
    assert parent.has_children?
    assert_not child.root?
    assert_not child.has_children?
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
end

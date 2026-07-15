require "test_helper"

class FootprintTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
  end

  test "valid with organization and name" do
    footprint = Footprint.new(organization: @org, name: "0805")
    assert footprint.valid?
  end

  test "requires a name" do
    footprint = Footprint.new(organization: @org, name: "")
    assert_not footprint.valid?
    assert_includes footprint.errors[:name], "can't be blank"
  end

  test "rejects a name longer than 50 characters" do
    footprint = Footprint.new(organization: @org, name: "a" * 51)
    assert_not footprint.valid?
  end

  test "requires a unique name within the organization" do
    create_footprint(organization: @org, name: "SOT-23")
    dup = Footprint.new(organization: @org, name: "SOT-23")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "allows the same name in a different organization" do
    create_footprint(organization: @org, name: "SOT-23")
    dup = Footprint.new(organization: create_organization, name: "SOT-23")
    assert dup.valid?
  end

  test "rejects an unknown mounting type but allows a blank one" do
    assert_not Footprint.new(organization: @org, name: "x", mounting_type: "Surface").valid?
    assert Footprint.new(organization: @org, name: "y", mounting_type: "").valid?
    assert Footprint.new(organization: @org, name: "z", mounting_type: "SMD").valid?
  end

  test "mounting-type predicates reflect the stored value" do
    assert Footprint.new(mounting_type: "SMD").smd?
    assert Footprint.new(mounting_type: "Through-hole").through_hole?
    assert_not Footprint.new(mounting_type: "Both").smd?
  end

  test "cannot be destroyed while parts reference it" do
    footprint = create_footprint(organization: @org)
    create_part(organization: @org, footprint: footprint)

    assert_no_difference "Footprint.count" do
      assert_not footprint.destroy
    end
    assert_includes footprint.errors[:base].join, "part"
  end
end

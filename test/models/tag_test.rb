require "test_helper"

class TagTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
  end

  test "valid with organization and name" do
    tag = Tag.new(organization: @org, name: "RoHS")
    assert tag.valid?
  end

  test "requires a name" do
    tag = Tag.new(organization: @org, name: "")
    assert_not tag.valid?
    assert_includes tag.errors[:name], "can't be blank"
  end

  test "rejects a name longer than 50 characters" do
    tag = Tag.new(organization: @org, name: "a" * 51)
    assert_not tag.valid?
  end

  test "requires a unique name within the organization" do
    create_tag(organization: @org, name: "favorite")
    dup = Tag.new(organization: @org, name: "favorite")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "allows the same name in a different organization" do
    create_tag(organization: @org, name: "favorite")
    other_org = create_organization
    dup = Tag.new(organization: other_org, name: "favorite")
    assert dup.valid?
  end

  test "accepts a valid hex color" do
    tag = Tag.new(organization: @org, name: "green", color: "#22C55E")
    assert tag.valid?
  end

  test "rejects an invalid color" do
    tag = Tag.new(organization: @org, name: "bad", color: "green")
    assert_not tag.valid?
  end

  test "color is optional" do
    tag = Tag.new(organization: @org, name: "plain", color: "")
    assert tag.valid?
  end

  test "most_used orders tags by the number of parts" do
    popular = create_tag(organization: @org, name: "popular")
    rare = create_tag(organization: @org, name: "rare")
    create_part(organization: @org).tags << popular
    create_part(organization: @org).tags << popular
    create_part(organization: @org).tags << rare

    assert_equal popular, @org.tags.most_used.first
  end

  test "destroying a tag removes its part associations but keeps the parts" do
    tag = create_tag(organization: @org)
    part = create_part(organization: @org)
    part.tags << tag

    assert_difference -> { PartTag.count } => -1 do
      tag.destroy
    end

    assert Part.exists?(part.id)
  end
end

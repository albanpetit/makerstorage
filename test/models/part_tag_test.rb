require "test_helper"

class PartTagTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @part = create_part(organization: @org)
    @tag = create_tag(organization: @org)
  end

  test "valid when part and tag belong to the same organization" do
    assert PartTag.new(part: @part, tag: @tag).valid?
  end

  test "rejects a duplicate tag on the same part" do
    PartTag.create!(part: @part, tag: @tag)
    dup = PartTag.new(part: @part, tag: @tag)
    assert_not dup.valid?
    assert_includes dup.errors[:part_id], "has already been taken"
  end

  test "rejects a tag from another organization" do
    other_tag = create_tag(organization: create_organization)
    part_tag = PartTag.new(part: @part, tag: other_tag)
    assert_not part_tag.valid?
    assert_includes part_tag.errors[:tag], "must belong to the same organization as the part"
  end
end

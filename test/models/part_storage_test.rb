require "test_helper"

class PartStorageTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @location = create_storage_location(organization: @org)
  end

  test "valid with a part, location, and non-negative quantity" do
    ps = PartStorage.new(part: @part, storage_location: @location, quantity: 10)
    assert ps.valid?
  end

  test "rejects a negative quantity" do
    ps = PartStorage.new(part: @part, storage_location: @location, quantity: -1)
    assert_not ps.valid?
    assert_includes ps.errors[:quantity], "must be greater than or equal to 0"
  end

  test "rejects a non-integer quantity" do
    ps = PartStorage.new(part: @part, storage_location: @location, quantity: 1.5)
    assert_not ps.valid?
  end

  test "one row per part and location pair" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 5)
    dup = PartStorage.new(part: @part, storage_location: @location, quantity: 1)
    assert_not dup.valid?
    assert_includes dup.errors[:part_id], "has already been taken"
  end

  test "allows the same part at a different location" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 5)
    other_location = create_storage_location(organization: @org, name: "Other")
    other = PartStorage.new(part: @part, storage_location: other_location, quantity: 5)
    assert other.valid?
  end

  test "storage location must belong to the same organization as the part" do
    other_org = create_organization
    foreign_location = create_storage_location(organization: other_org)
    ps = PartStorage.new(part: @part, storage_location: foreign_location, quantity: 1)
    assert_not ps.valid?
    assert_includes ps.errors[:storage_location], "must belong to the same organization as the part"
  end

  test "with_stock and empty scopes" do
    stocked = PartStorage.create!(part: @part, storage_location: @location, quantity: 5)
    other_part = create_part(organization: @org, category: @category)
    empty = PartStorage.create!(part: other_part, storage_location: @location, quantity: 0)

    assert_includes PartStorage.with_stock, stocked
    assert_not_includes PartStorage.with_stock, empty
    assert_includes PartStorage.empty, empty
    assert_not_includes PartStorage.empty, stocked
  end
end

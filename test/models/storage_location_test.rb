require "test_helper"

class StorageLocationTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
  end

  test "valid with organization, name, and location_type" do
    location = StorageLocation.new(organization: @org, name: "Workshop", location_type: "room")
    assert location.valid?
  end

  test "rejects a location_type outside the allowed list" do
    location = StorageLocation.new(organization: @org, name: "Workshop", location_type: "warehouse")
    assert_not location.valid?
    assert_includes location.errors[:location_type], "is not included in the list"
  end

  test "accepts every declared location type" do
    StorageLocation::LOCATION_TYPES.each do |type|
      location = StorageLocation.new(organization: @org, name: "X", location_type: type)
      assert location.valid?, "expected location_type #{type} to be valid"
    end
  end

  test "cannot be its own parent" do
    location = create_storage_location(organization: @org)
    location.parent_id = location.id
    assert_not location.valid?
    assert_includes location.errors[:parent_id], "cannot be itself"
  end

  test "parent must belong to the same organization" do
    other_org = create_organization
    parent = create_storage_location(organization: other_org)
    child = StorageLocation.new(organization: @org, name: "Box", location_type: "box", parent: parent)
    assert_not child.valid?
    assert_includes child.errors[:parent], "must belong to the same organization"
  end

  test "cannot be moved under one of its own descendants" do
    room = create_storage_location(organization: @org, location_type: "room")
    cabinet = create_storage_location(organization: @org, location_type: "cabinet", parent: room)
    box = create_storage_location(organization: @org, location_type: "box", parent: cabinet)

    room.parent = box
    assert_not room.valid?
    assert_includes room.errors[:parent_id], "cannot be moved under one of its own sub-zones"
  end

  test "can be moved under an unrelated zone" do
    room_a = create_storage_location(organization: @org, name: "Room A", location_type: "room")
    room_b = create_storage_location(organization: @org, name: "Room B", location_type: "room")
    box = create_storage_location(organization: @org, location_type: "box", parent: room_a)

    box.parent = room_b
    assert box.valid?
  end

  test "root? and has_children?" do
    room = create_storage_location(organization: @org, location_type: "room")
    box = create_storage_location(organization: @org, location_type: "box", parent: room)

    assert room.root?
    assert room.has_children?
    assert_not box.root?
    assert_not box.has_children?
  end

  test "full_path builds the breadcrumb from ancestors" do
    room = create_storage_location(organization: @org, name: "Workshop", location_type: "room")
    cabinet = create_storage_location(organization: @org, name: "Cabinet A", location_type: "cabinet", parent: room)
    box = create_storage_location(organization: @org, name: "Box A1", location_type: "box", parent: cabinet)

    assert_equal "Workshop > Cabinet A > Box A1", box.full_path
  end

  test "full_path resolves ancestry from a preloaded cache without extra queries" do
    room = create_storage_location(organization: @org, name: "Workshop", location_type: "room")
    cabinet = create_storage_location(organization: @org, name: "Cabinet A", location_type: "cabinet", parent: room)
    box = create_storage_location(organization: @org, name: "Box A1", location_type: "box", parent: cabinet)

    cache = StorageLocation.full_path_cache(@org.storage_locations)

    assert_no_queries do
      assert_equal "Workshop > Cabinet A > Box A1", box.full_path(cache: cache)
    end
  end

  test "ancestors and descendants" do
    room = create_storage_location(organization: @org, name: "Workshop", location_type: "room")
    cabinet = create_storage_location(organization: @org, name: "Cabinet A", location_type: "cabinet", parent: room)
    box = create_storage_location(organization: @org, name: "Box A1", location_type: "box", parent: cabinet)

    assert_equal [ cabinet, room ], box.ancestors
    assert_equal [ cabinet, box ], room.descendants
  end

  test "total_quantity sums part_storages at this location" do
    location = create_storage_location(organization: @org)
    category = create_category(organization: @org)
    part_a = create_part(organization: @org, category: category)
    part_b = create_part(organization: @org, category: category)
    PartStorage.create!(part: part_a, storage_location: location, quantity: 10)
    PartStorage.create!(part: part_b, storage_location: location, quantity: 25)

    assert_equal 35, location.total_quantity
  end

  test "destroy is blocked, not a crash, while an open order targets the zone" do
    org = create_organization
    zone = create_storage_location(organization: org)
    part = create_part(organization: org)
    line = create_order(organization: org, reference: "PO-1").order_lines.create!(part: part, quantity: 4)
    line.allocations.create!(storage_location: zone, quantity: 4)

    assert_not zone.destroy
    assert_predicate zone.errors[:base], :any?
    assert StorageLocation.exists?(zone.id)
  end

  test "codes are unique per organization, ignoring case, so scans aren't ambiguous" do
    org = create_organization
    create_storage_location(organization: org, code: "DRW-01")

    duplicate = StorageLocation.new(organization: org, name: "Other", location_type: "drawer", code: "drw-01")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"

    assert StorageLocation.new(organization: create_organization, name: "Elsewhere", location_type: "drawer", code: "DRW-01").valid?
    assert StorageLocation.new(organization: org, name: "Uncoded", location_type: "drawer", code: "").valid?
  end
end

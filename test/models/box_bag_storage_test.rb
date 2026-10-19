require "test_helper"

# Box & bag numbering (Organization ipn_generation_mode "box_bag"): bags are
# numbered zones inside a coded box, and a part's IPN is the code of its bag.
class BoxBagStorageTest < ActiveSupport::TestCase
  setup do
    # A signed-up user's own organization, so it has the owner updates need.
    @org = create_user.organizations.first
    @org.update!(ipn_generation_mode: "box_bag")
    @box_a = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    @box_b = create_storage_location(organization: @org, name: "Box B", location_type: "box", code: "B")
  end

  def stock(part, bag, delta)
    @org.stock_movements.create!(part: part, storage_location: bag, movement_type: delta.positive? ? "in" : "out", quantity_delta: delta)
  end

  test "bags are numbered inside their box and coded from it" do
    bags = @box_a.add_bags!(3)

    assert_equal [ 1, 2, 3 ], bags.map(&:position)
    assert_equal %w[A-1 A-2 A-3], bags.map(&:code)
    assert_equal "Bag A-1", bags.first.name
    assert_equal [ "A-4" ], @box_a.add_bags!(1).map(&:code)
  end

  test "a bag must sit in a box that has a code" do
    shelf = create_storage_location(organization: @org, location_type: "shelf")
    bag = @org.storage_locations.build(location_type: "bag", parent: shelf)
    assert_not bag.valid?
    assert_includes bag.errors[:parent].join, "must be a box"

    uncoded = create_storage_location(organization: @org, location_type: "box")
    bag = @org.storage_locations.build(location_type: "bag", parent: uncoded)
    assert_not bag.valid?
    assert_includes bag.errors[:parent].join, "needs a code"
  end

  test "a box holding bags keeps its code, and renaming it renames its bags and their parts' IPNs" do
    bag = @box_a.add_bags!(1).first
    part = create_part(organization: @org)
    assert_equal "A-1", part.reload.ipn

    assert_not @box_a.update(code: "")
    assert @box_a.update(code: "Z")

    assert_equal "Z-1", bag.reload.code
    assert_equal "Z-1", part.reload.ipn
  end

  test "a new part takes the first free bag, box by box, and its code as IPN" do
    @box_b.add_bags!(1)
    @box_a.add_bags!(2)

    first = create_part(organization: @org)
    second = create_part(organization: @org)
    third = create_part(organization: @org)

    assert_equal %w[A-1 A-2 B-1], [ first, second, third ].map { |part| part.reload.ipn }
    assert_equal "A-1", first.bag.code
    assert_not_nil first.bag_assigned_at
  end

  test "with no free bag a new part is created without an IPN" do
    part = create_part(organization: @org)

    assert_nil part.bag
    assert_nil part.ipn
  end

  test "a part that hasn't been stocked yet keeps its bag" do
    @box_a.add_bags!(1)
    create_part(organization: @org)

    assert_empty @org.free_bags
    assert_nil create_part(organization: @org).ipn
  end

  test "an emptied bag is free again and goes to the next new part" do
    bag = @box_a.add_bags!(1).first
    old = create_part(organization: @org)
    stock(old, bag, 10)
    assert_empty @org.free_bags

    stock(old, bag, -10)
    assert_equal [ bag ], @org.free_bags.to_a
    # The old part keeps its bag until another part takes it...
    assert_equal "A-1", old.reload.ipn

    new_part = create_part(organization: @org)

    assert_equal "A-1", new_part.reload.ipn
    assert_nil old.reload.bag
    assert_nil old.ipn
    # ...and its empty stock row in the bag goes away.
    assert_not PartStorage.exists?(part: old, storage_location: bag)
  end

  test "restocking a bag before it's reused keeps it with its part" do
    bag = @box_a.add_bags!(1).first
    part = create_part(organization: @org)
    stock(part, bag, 5)
    stock(part, bag, -5)
    stock(part, bag, 3)

    assert_empty @org.free_bags
  end

  test "a bag still holding another part's stock is never free" do
    bag1, bag2 = @box_a.add_bags!(2)
    first = create_part(organization: @org)
    second = create_part(organization: @org)
    stock(first, bag1, 5)
    # The first part's stock lands in the second's bag before the second gives it up.
    second.update!(bag: nil)
    @org.update!(ipn_generation_mode: "incremental")
    stock(first, bag2, 5)
    @org.update!(ipn_generation_mode: "box_bag")

    assert_empty @org.free_bags
    assert_nil create_part(organization: @org).bag
    # The part whose stock is there can still take it.
    assert_includes @org.free_bags(for_part: first).to_a, bag2
  end

  test "stock can't go into a bag another part holds" do
    bag1, bag2 = @box_a.add_bags!(2)
    first = create_part(organization: @org)
    create_part(organization: @org)

    movement = @org.stock_movements.build(part: first, storage_location: bag2, movement_type: "in", quantity_delta: 3)
    assert_not movement.valid?
    assert_includes movement.errors[:storage_location].join, "A-2"

    assert @org.stock_movements.build(part: first, storage_location: bag1, movement_type: "in", quantity_delta: 3).valid?
  end

  test "picking an occupied bag is refused" do
    bag = @box_a.add_bags!(1).first
    create_part(organization: @org)
    other = create_part(organization: @org)

    other.bag = bag
    assert_not other.valid?
    assert_includes other.errors[:bag].join, "already holding another part"
  end

  test "a bag from another organization is refused" do
    other_org = create_organization(ipn_generation_mode: "box_bag")
    foreign_box = create_storage_location(organization: other_org, location_type: "box", code: "A")
    foreign_bag = foreign_box.add_bags!(1).first

    part = create_part(organization: @org)
    part.bag = foreign_bag
    assert_not part.valid?
    assert_includes part.errors[:bag].join, "must be a bag of this organization"
  end

  test "bags of another organization are never offered" do
    other_org = create_organization(ipn_generation_mode: "box_bag")
    create_storage_location(organization: other_org, location_type: "box", code: "A").add_bags!(2)

    assert_empty @org.free_bags
    assert_nil create_part(organization: @org).ipn
  end

  test "moving a part to another bag changes its IPN" do
    bag1, bag2 = @box_a.add_bags!(2)
    part = create_part(organization: @org, bag: bag1)
    assert_equal "A-1", part.reload.ipn

    part.update!(bag: bag2)
    assert_equal "A-2", part.reload.ipn
    assert_includes @org.free_bags, bag1

    part.update!(bag: nil)
    assert_nil part.reload.ipn
  end

  test "deleting a bag releases its part" do
    bag = @box_a.add_bags!(1).first
    part = create_part(organization: @org)

    bag.destroy!

    assert_nil part.reload.bag_id
    assert_nil part.ipn
  end

  test "other numbering modes ignore bags" do
    org = create_organization
    create_storage_location(organization: org, location_type: "box", code: "A").add_bags!(1)

    part = create_part(organization: org)
    assert_nil part.bag
    assert_match(/\AMS-/, part.ipn)
  end

  test "changing the separator recodes the bags and their parts" do
    bag = @box_a.add_bags!(1).first
    part = create_part(organization: @org)

    @org.update!(ipn_separator: ".")

    assert_equal "A.1", bag.reload.code
    assert_equal "A.1", part.reload.ipn
  end

  test "renaming a box onto codes another part already has as IPN is refused" do
    bag = @box_a.add_bags!(1).first
    occupant = create_part(organization: @org)
    other = create_part(organization: @org, ipn: "b-1")

    assert_not @box_a.update(code: "B")
    assert_includes @box_a.errors[:code].join, "B-1"
    assert_equal "A-1", bag.reload.code
    assert_equal "A-1", occupant.reload.ipn
    assert_equal "b-1", other.reload.ipn
  end

  test "renaming a box onto another zone's codes is refused" do
    @box_a.add_bags!(1)
    create_storage_location(organization: @org, name: "Drawer", location_type: "drawer", code: "C-1")

    assert_not @box_a.update(code: "C")
    assert_includes @box_a.errors[:code].join, "C-1"
  end

  test "changing the separator onto codes already in use is refused" do
    @box_a.add_bags!(1)
    create_part(organization: @org)
    create_storage_location(organization: @org, name: "Drawer", location_type: "drawer", code: "A.1")

    assert_not @org.update(ipn_separator: ".")
    assert_includes @org.errors[:ipn_separator].join, "A.1"
    assert_equal "A-1", @box_a.children.bags.first.code
  end

  test "reassigning IPNs gives stocked parts the bags they sit in" do
    bag1, bag2 = @box_a.add_bags!(2)
    @org.update!(ipn_generation_mode: "incremental")
    in_bag = create_part(organization: @org)
    elsewhere = create_part(organization: @org)
    stock(in_bag, bag2, 4)
    stock(elsewhere, create_storage_location(organization: @org, location_type: "shelf"), 4)
    @org.update!(ipn_generation_mode: "box_bag")

    assert_equal 2, @org.reassign_ipns!(clear_unbagged: true)

    assert_equal bag2, in_bag.reload.bag
    assert_equal "A-2", in_bag.ipn
    assert_nil elsewhere.reload.ipn
    assert_includes @org.free_bags, bag1
  end

  test "reassigning IPNs keeps the reference of parts without a bag by default" do
    bag = @box_a.add_bags!(1).first
    @org.update!(ipn_generation_mode: "incremental")
    in_bag = create_part(organization: @org)
    elsewhere = create_part(organization: @org)
    old_ipn = elsewhere.ipn
    stock(in_bag, bag, 2)
    @org.update!(ipn_generation_mode: "box_bag")

    assert_equal 1, @org.reassign_ipns!

    assert_equal "A-1", in_bag.reload.ipn
    assert_equal old_ipn, elsewhere.reload.ipn
    assert_nil elsewhere.bag
  end

  test "reassigning IPNs clears a kept reference that a bag code takes over" do
    bag = @box_a.add_bags!(1).first
    @org.update!(ipn_generation_mode: "manual")
    squatter = create_part(organization: @org, ipn: "a-1")
    in_bag = create_part(organization: @org, ipn: "OLD")
    stock(in_bag, bag, 2)
    @org.update!(ipn_generation_mode: "box_bag")

    assert_equal 2, @org.reassign_ipns!

    assert_equal "A-1", in_bag.reload.ipn
    assert_nil squatter.reload.ipn
  end

  test "the reassignment plan shows the changes without writing them" do
    bag = @box_a.add_bags!(1).first
    @org.update!(ipn_generation_mode: "manual")
    holder = create_part(organization: @org, ipn: "A-1", bag: bag)
    in_bag = create_part(organization: @org, ipn: "OLD")
    stock(in_bag, @box_a.add_bags!(1).first, 2)
    untouched = create_part(organization: @org, ipn: "KEEP")
    @org.update!(ipn_generation_mode: "box_bag")

    entries = @org.ipn_reassignment_plan[:entries].index_by { |entry| entry[:part] }

    assert_not entries[holder][:changed]
    assert_equal [ "OLD", "A-2", true ], entries[in_bag].values_at(:from, :to, :changed)
    assert entries[in_bag][:takes_bag]
    assert_not entries[untouched][:changed]
    assert_equal [ "KEEP", nil ], @org.ipn_reassignment_plan(clear_unbagged: true)[:entries].find { |e| e[:part] == untouched }.values_at(:from, :to)
    assert_equal "OLD", in_bag.reload.ipn
    assert_nil in_bag.bag
  end

  test "ipn_preview lists the next free bags" do
    @box_a.add_bags!(3)

    assert_equal({ next: "A-1", examples: %w[A-2 A-3] }, @org.ipn_preview(example_count: 2))
  end
end

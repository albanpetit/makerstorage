require "test_helper"

class StocktakeTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @user = create_user
    @cabinet = create_storage_location(organization: @org, name: "Cabinet", location_type: "cabinet")
    @drawer = create_storage_location(organization: @org, name: "Drawer 1", location_type: "drawer", parent: @cabinet)
    @other_zone = create_storage_location(organization: @org, name: "Shelf")
    @resistor = create_part(organization: @org, name: "Resistor 10k")
    @cap = create_part(organization: @org, name: "Cap 100nF")
    stock(@resistor, @drawer, 50)
    stock(@cap, @cabinet, 10)
    stock(@cap, @other_zone, 7)
  end

  test "starting a count lists the stock of the zone and its sub-zones" do
    stocktake = start(@cabinet)

    lines = stocktake.stocktake_lines.map { |line| [ line.part, line.storage_location, line.expected_quantity ] }
    assert_equal [ [ @cap, @cabinet, 10 ], [ @resistor, @drawer, 50 ] ].sort_by { |l| l[0].id }, lines.sort_by { |l| l[0].id }
    assert_match(/\AST-\d{8}-1\z/, stocktake.reference)
  end

  test "a count without sub-zones lists only the zone itself" do
    stocktake = start(@cabinet, include_sub_zones: false)

    assert_equal [ @cabinet.id ], stocktake.location_ids
    assert_equal [ @cap ], stocktake.stocktake_lines.map(&:part)
  end

  test "empty stock rows are left out of the snapshot" do
    StockMovement.create!(organization: @org, part: @cap, storage_location: @cabinet, movement_type: "out", quantity_delta: -10)

    assert_equal [ @resistor ], start(@cabinet).stocktake_lines.map(&:part)
  end

  test "two counts can't run over the same zone" do
    first = start(@cabinet)
    overlapping = @org.stocktakes.new(storage_location: @drawer)

    assert_not overlapping.valid?
    assert_match(/already being counted in #{first.reference}/, overlapping.errors.full_messages.to_sentence)
    assert @org.stocktakes.new(storage_location: @other_zone).valid?

    first.complete!(user: @user)
    assert overlapping.valid?
  end

  test "a zone from another organization is rejected" do
    foreign = create_storage_location(organization: create_organization)

    stocktake = @org.stocktakes.new(storage_location: foreign)
    assert_not stocktake.valid?
    assert_includes stocktake.errors[:storage_location], "must belong to the same organization"
  end

  test "a line must sit in a counted zone and hold a part of the organization" do
    stocktake = start(@cabinet, include_sub_zones: false)

    outside = stocktake.stocktake_lines.new(part: @resistor, storage_location: @drawer)
    assert_not outside.valid?
    assert_includes outside.errors[:storage_location], "isn't part of this stocktake"

    foreign_part = create_part(organization: create_organization)
    line = stocktake.stocktake_lines.new(part: foreign_part, storage_location: @cabinet)
    assert_not line.valid?
    assert_includes line.errors[:part], "must belong to the same organization"
  end

  test "counting refreshes what the ledger expects to the stock at that moment" do
    stocktake = start(@cabinet)
    line = line_for(stocktake, @resistor)
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -5)

    stocktake.count!(line, 44, user: @user)

    assert_equal 45, line.reload.expected_quantity
    assert_equal 44, line.counted_quantity
    assert_equal(-1, line.difference)
    assert_equal @user, line.counted_by
  end

  test "a cleared count goes back to not counted" do
    stocktake = start(@cabinet)
    line = line_for(stocktake, @cap)
    stocktake.count!(line, 3, user: @user)
    stocktake.count!(line, nil, user: @user)

    assert_not line.reload.counted?
    assert_nil line.counted_at
    assert_nil line.counted_by
  end

  test "a negative count is refused" do
    stocktake = start(@cabinet)

    assert_raises(ActiveRecord::RecordInvalid) { stocktake.count!(line_for(stocktake, @cap), -1, user: @user) }
  end

  test "completing writes an adjustment for each counted difference" do
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @resistor), 47, user: @user)
    stocktake.count!(line_for(stocktake, @cap), 12, user: @user)

    assert_difference -> { StockMovement.count } => 2 do
      assert_equal 2, stocktake.complete!(user: @user)
    end

    assert_equal 47, quantity(@resistor, @drawer)
    assert_equal 12, quantity(@cap, @cabinet)
    assert_equal 7, quantity(@cap, @other_zone)

    adjustment = line_for(stocktake, @resistor).stock_movement
    assert_equal "adjustment", adjustment.movement_type
    assert_equal(-3, adjustment.quantity_delta)
    assert_equal Stocktake::MOVEMENT_REASON, adjustment.reason
    assert_equal stocktake.reference, adjustment.reference
    assert_equal @user, adjustment.user

    assert stocktake.reload.completed?
    assert_equal @user, stocktake.completed_by
    assert_not_nil stocktake.completed_at
  end

  test "a count matching the stock writes nothing" do
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @cap), 10, user: @user)

    assert_no_difference -> { StockMovement.count } do
      assert_equal 0, stocktake.complete!(user: @user)
    end
    assert_nil line_for(stocktake, @cap).stock_movement
  end

  test "stock moved after a line was counted is kept" do
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @resistor), 48, user: @user)
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -10)

    stocktake.complete!(user: @user)

    # 50 expected, 48 counted: -2, on top of the 10 taken since.
    assert_equal 38, quantity(@resistor, @drawer)
  end

  test "uncounted lines are left alone unless taken as empty" do
    stocktake = start(@cabinet)
    stocktake.complete!(user: @user)
    assert_equal 50, quantity(@resistor, @drawer)

    other = start(@cabinet)
    other.complete!(user: @user, zero_uncounted: true)
    assert_equal 0, quantity(@resistor, @drawer)
    assert_equal 0, quantity(@cap, @cabinet)
    assert_equal 0, line_for(other, @cap).counted_quantity
  end

  test "a part found where the ledger had none is added and credited" do
    stocktake = start(@cabinet)
    line = stocktake.line_for!(@resistor, @cabinet)
    assert_equal 0, line.expected_quantity

    stocktake.count!(line, 4, user: @user)
    stocktake.complete!(user: @user)

    assert_equal 4, quantity(@resistor, @cabinet)
  end

  test "completing is all or nothing when the ledger refuses an adjustment" do
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @cap), 12, user: @user)
    stocktake.count!(line_for(stocktake, @resistor), 0, user: @user)
    # 30 taken out after the count: removing the 50 expected would overdraw.
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -30)

    assert_no_difference -> { StockMovement.count } do
      assert_raises(ActiveRecord::RecordInvalid) { stocktake.complete!(user: @user) }
    end
    assert stocktake.reload.in_progress?
    assert_equal 10, quantity(@cap, @cabinet)
    assert_nil line_for(stocktake, @cap).stock_movement_id
  end

  test "the overdraw is accepted when the organization allows negative stock" do
    @org.update_column(:allow_negative_stock, true)
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @resistor), 0, user: @user)
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -30)

    stocktake.complete!(user: @user)
    assert_equal(-30, quantity(@resistor, @drawer))
  end

  test "a completed stocktake can't be counted or completed again" do
    stocktake = start(@cabinet)
    stocktake.count!(line_for(stocktake, @cap), 11, user: @user)
    stocktake.complete!(user: @user)

    assert_raises(Stocktake::NotInProgress) { stocktake.count!(line_for(stocktake, @cap), 20, user: @user) }
    assert_raises(Stocktake::NotInProgress) { stocktake.line_for!(@resistor, @cabinet) }
    assert_no_difference -> { StockMovement.count } do
      assert_raises(Stocktake::NotInProgress) { stocktake.complete!(user: @user) }
    end
    assert_equal 11, quantity(@cap, @cabinet)
  end

  test "last_counted_at_by_zone covers sub-zones of completed counts only" do
    travel_to 10.days.ago do
      stocktake = start(@cabinet)
      stocktake.complete!(user: @user)
    end
    start(@other_zone)

    counted = Stocktake.last_counted_at_by_zone(@org)
    assert_in_delta 10.days.ago, counted[@cabinet.id], 1.minute
    assert_in_delta 10.days.ago, counted[@drawer.id], 1.minute
    assert_not counted.key?(@other_zone.id)
  end

  test "deleting a counted zone or part takes its lines with it" do
    bin = create_storage_location(organization: @org, name: "Bin")
    spare = create_part(organization: @org)
    stocktake = start(bin)
    stocktake.line_for!(spare, bin)
    stocktake.line_for!(@cap, bin)

    assert_difference -> { StocktakeLine.count }, -1 do
      assert spare.destroy
    end
    assert_difference -> { Stocktake.count } => -1, -> { StocktakeLine.count } => -1 do
      assert bin.destroy
    end
  end

  test "deleting a user keeps their stocktakes" do
    stocktake = start(@cabinet)
    stocktake.update!(user: @user)
    stocktake.count!(line_for(stocktake, @cap), 10, user: @user)
    stocktake.complete!(user: @user)

    # A second owner, so the sole-owner guard doesn't block removing the user.
    OrganizationMembership.create!(organization: @user.organizations.first, user: create_user, role: "owner")
    @user.destroy!
    stocktake.reload
    assert_nil stocktake.user
    assert_nil stocktake.completed_by
    assert_nil line_for(stocktake, @cap).counted_by
  end

  private

  def stock(part, location, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  def start(location, **attrs)
    stocktake = @org.stocktakes.new(storage_location: location, **attrs)
    stocktake.save_with_generated_reference! { Stocktake.next_reference(@org) }
    stocktake.snapshot_stock!
    stocktake
  end

  def line_for(stocktake, part)
    stocktake.stocktake_lines.find_by!(part: part)
  end

  def quantity(part, location)
    PartStorage.find_by(part: part, storage_location: location)&.quantity
  end
end

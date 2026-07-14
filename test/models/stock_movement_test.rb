require "test_helper"

class StockMovementTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @location = create_storage_location(organization: @org)
  end

  test "valid incoming movement" do
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "in", quantity_delta: 10
    )
    assert movement.valid?
  end

  test "rejects a movement_type outside the allowed list" do
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "transfer", quantity_delta: 10
    )
    assert_not movement.valid?
    assert_includes movement.errors[:movement_type], "is not included in the list"
  end

  test "rejects a zero quantity_delta" do
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "adjustment", quantity_delta: 0
    )
    assert_not movement.valid?
    assert_includes movement.errors[:quantity_delta], "must be other than 0"
  end

  test "an incoming movement must have a positive delta" do
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "in", quantity_delta: -5
    )
    assert_not movement.valid?
    assert_includes movement.errors[:quantity_delta], "must be positive for an incoming movement"
  end

  test "an outgoing movement must have a negative delta" do
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "out", quantity_delta: 5
    )
    assert_not movement.valid?
    assert_includes movement.errors[:quantity_delta], "must be negative for an outgoing movement"
  end

  test "an adjustment can go either direction" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 10)

    positive = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "adjustment", quantity_delta: 3
    )
    negative = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "adjustment", quantity_delta: -3
    )
    assert positive.valid?
    assert negative.valid?
  end

  test "storage location must belong to the same organization" do
    other_org = create_organization
    foreign_location = create_storage_location(organization: other_org)
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: foreign_location,
      movement_type: "in", quantity_delta: 5
    )
    assert_not movement.valid?
    assert_includes movement.errors[:storage_location], "must belong to the same organization"
  end

  test "blocks a movement that would push stock negative" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 5)
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "out", quantity_delta: -10
    )
    assert_not movement.valid?
    assert_includes movement.errors[:quantity_delta], "would result in negative stock at this location"
  end

  # The apply step must enforce the non-negative guard atomically, not just the
  # advisory validation. Simulate the concurrency race by bypassing validation
  # (as if it had passed against stale stock a concurrent movement then consumed):
  # the apply step must still refuse to drive the stored quantity negative.
  test "apply step atomically refuses to overdraw even when validation is bypassed" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 5)
    movement = StockMovement.new(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "out", quantity_delta: -10
    )

    assert_not movement.save(validate: false), "apply guard should abort the overdraw"
    assert_includes movement.errors[:quantity_delta], "would result in negative stock at this location"
    assert_not movement.persisted?, "the overdrawing movement must not be recorded"
    assert_equal 5, PartStorage.find_by(part: @part, storage_location: @location).quantity,
      "stored quantity must be untouched"
  end

  test "apply step still allows an overdraw when the organization permits negative stock" do
    org = create_organization(allow_negative_stock: true)
    category = create_category(organization: org)
    part = create_part(organization: org, category: category)
    location = create_storage_location(organization: org)
    PartStorage.create!(part: part, storage_location: location, quantity: 5)

    movement = StockMovement.new(
      organization: org, part: part, storage_location: location,
      movement_type: "out", quantity_delta: -10
    )

    assert movement.save
    assert_equal(-5, PartStorage.find_by(part: part, storage_location: location).quantity)
  end

  test "allows a negative result when the organization permits it" do
    org = create_organization(allow_negative_stock: true)
    category = create_category(organization: org)
    part = create_part(organization: org, category: category)
    location = create_storage_location(organization: org)
    PartStorage.create!(part: part, storage_location: location, quantity: 5)

    movement = StockMovement.new(
      organization: org, part: part, storage_location: location,
      movement_type: "out", quantity_delta: -10
    )
    assert movement.valid?
  end

  test "creating a movement updates the part storage quantity" do
    assert_difference -> { @part.reload.total_quantity }, 25 do
      StockMovement.create!(
        organization: @org, part: @part, storage_location: @location,
        movement_type: "in", quantity_delta: 25
      )
    end

    assert_difference -> { @part.reload.total_quantity }, -10 do
      StockMovement.create!(
        organization: @org, part: @part, storage_location: @location,
        movement_type: "out", quantity_delta: -10
      )
    end
  end

  test "creates a part_storage row on first movement if one doesn't exist yet" do
    assert_nil PartStorage.find_by(part: @part, storage_location: @location)

    StockMovement.create!(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "in", quantity_delta: 15
    )

    ps = PartStorage.find_by(part: @part, storage_location: @location)
    assert_not_nil ps
    assert_equal 15, ps.quantity
  end

  test "type predicate methods" do
    movement = StockMovement.create!(
      organization: @org, part: @part, storage_location: @location,
      movement_type: "in", quantity_delta: 5
    )
    assert movement.in?
    assert_not movement.out?
    assert_not movement.adjustment?
  end

  test "scopes filter by movement type" do
    PartStorage.create!(part: @part, storage_location: @location, quantity: 100)
    inbound = StockMovement.create!(organization: @org, part: @part, storage_location: @location, movement_type: "in", quantity_delta: 5)
    outbound = StockMovement.create!(organization: @org, part: @part, storage_location: @location, movement_type: "out", quantity_delta: -5)
    adjustment = StockMovement.create!(organization: @org, part: @part, storage_location: @location, movement_type: "adjustment", quantity_delta: 2)

    assert_equal [ inbound ], StockMovement.inbound.to_a
    assert_equal [ outbound ], StockMovement.outbound.to_a
    assert_equal [ adjustment ], StockMovement.adjustments.to_a
  end
end

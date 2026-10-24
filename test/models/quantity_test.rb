require "test_helper"

class QuantityTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @zone = create_storage_location(organization: @organization)
    @wire = create_part(organization: @organization, name: "Hookup wire", unit: "meter")
    @resistor = create_part(organization: @organization, name: "Resistor 10k")
  end

  def move(part, delta, type: delta.to_d.positive? ? "in" : "out")
    @organization.stock_movements.create!(part: part, storage_location: @zone, movement_type: type, quantity_delta: delta)
  end

  test "parse reads dots, French commas and numbers, and rejects the rest" do
    assert_equal 2.5, Quantity.parse("2,5")
    assert_equal 2.5, Quantity.parse(" 2.5 ")
    assert_equal 3, Quantity.parse("3")
    assert_kind_of Integer, Quantity.parse("3.0")
    assert_equal 0.125, Quantity.parse(".125")
    assert_equal(-1.5, Quantity.parse("-1,5"))
    assert_equal 1.235, Quantity.parse("1.2345")
    assert_nil Quantity.parse("")
    assert_nil Quantity.parse("abc")
    assert_nil Quantity.parse("1,000.5")
  end

  test "format uses the locale's separator and a measure unit's symbol" do
    assert_equal "2.5 m", Quantity.format(2.5, "meter")
    assert_equal "12", Quantity.format(12, "piece")
    I18n.with_locale(:fr) { assert_equal "0,5 L", Quantity.format(0.5, "liter") }
  end

  test "quantity columns read whole values as integers and keep three decimals" do
    move(@wire, "2,5")
    move(@wire, 0.1)
    move(@wire, 0.2)
    storage = PartStorage.find_by!(part: @wire, storage_location: @zone)
    assert_equal 2.8, storage.quantity
    assert_equal 2.8, @wire.reload.total_quantity
    assert_equal "2.8", @wire.total_quantity.to_s

    move(@resistor, 10)
    assert_kind_of Integer, @resistor.reload.total_quantity
    assert_equal({ "quantity" => 10 }, PartStorage.find_by!(part: @resistor).as_json(only: :quantity))
  end

  test "a measure can be drawn down to exactly zero" do
    move(@wire, 0.3)
    move(@wire, -0.1)
    move(@wire, -0.2)
    assert_equal 0, @wire.reload.total_quantity
    assert_raises(ActiveRecord::RecordInvalid) { move(@wire, -0.001) }
  end

  test "count units only take whole quantities" do
    movement = @organization.stock_movements.build(part: @resistor, storage_location: @zone, movement_type: "in", quantity_delta: 2.5)
    assert_not movement.valid?
    assert movement.errors.added?(:quantity_delta, :whole_quantity_for_unit, unit: "pieces")

    assert move(@wire, 2.5).persisted?
  end

  test "garbage quantities are not numbers" do
    movement = @organization.stock_movements.build(part: @wire, storage_location: @zone, movement_type: "in", quantity_delta: "lots")
    assert_not movement.valid?
    assert movement.errors.added?(:quantity_delta, :not_a_number)
  end

  test "thresholds and pack sizes follow the part's unit" do
    @wire.update!(min_stock_threshold: 1.5, target_stock: 10.25, pack_size: 100)
    assert_equal 1.5, @wire.reload.min_stock_threshold
    assert @wire.low_stock?

    @resistor.min_stock_threshold = 2.5
    assert_not @resistor.valid?
    assert @resistor.errors.added?(:min_stock_threshold, :whole_quantity_for_unit, unit: "pieces")
  end

  test "a part holding fractional stock can't switch to a count unit" do
    move(@wire, 2.5)
    @wire.unit = "piece"
    assert_not @wire.valid?
    assert @wire.errors.added?(:unit, :fractional_stock, unit: "pieces")

    @wire.unit = "liter"
    assert @wire.valid?

    move(@wire, 0.5)
    @wire.unit = "piece"
    assert @wire.valid?, "3 m reads as 3 pieces"
  end

  test "low stock scopes compare decimal totals" do
    @wire.update!(min_stock_threshold: 3)
    move(@wire, 2.5)
    assert_includes @organization.parts.low_stock.to_a, @wire
    move(@wire, 0.5)
    assert_not_includes @organization.parts.low_stock.to_a, @wire
  end
end

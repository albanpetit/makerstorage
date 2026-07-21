require "test_helper"

class ProjectLineTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @project = create_project(organization: @org)
    @part = create_part(organization: @org)
    @location = create_storage_location(organization: @org)
  end

  test "quantity must be a positive integer" do
    line = @project.project_lines.build(quantity: 0, match_type: "none")
    assert_not line.valid?
    assert_includes line.errors[:quantity], "must be greater than 0"
  end

  test "match_type must be one of the allowed values" do
    line = @project.project_lines.build(quantity: 1, match_type: "guessed")
    assert_not line.valid?
  end

  test "matched part must belong to the project's organization" do
    other_part = create_part(organization: create_organization)
    line = @project.project_lines.build(part: other_part, quantity: 1, match_type: "manual")
    assert_not line.valid?
    assert_includes line.errors[:part], "must belong to the same organization"
  end

  test "availability helpers reflect stock" do
    stock(6)
    line = @project.project_lines.create!(part: @part, quantity: 4, match_type: "mpn")

    assert_equal 6, line.in_stock
    assert_equal 0, line.shortfall
    assert line.available?
  end

  test "shortfall is the unmet quantity when stock is insufficient" do
    stock(3)
    line = @project.project_lines.create!(part: @part, quantity: 10, match_type: "mpn")

    assert_equal 7, line.shortfall
    assert_not line.available?
  end

  test "an unmatched line is never available and has no shortfall" do
    line = @project.project_lines.create!(quantity: 5, match_type: "none")

    assert_equal 0, line.in_stock
    assert_equal 0, line.shortfall
    assert_not line.available?
  end

  private

  def stock(quantity)
    StockMovement.create!(organization: @org, part: @part, storage_location: @location,
      movement_type: "in", quantity_delta: quantity)
  end
end

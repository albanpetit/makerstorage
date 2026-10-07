require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
  end

  test "requires a name of at least 2 characters" do
    assert_not Project.new(organization: @org, name: "a").valid?
    assert Project.new(organization: @org, name: "Kit").valid?
  end

  test "status must be one of the allowed values" do
    project = Project.new(organization: @org, name: "Kit", status: "bogus")
    assert_not project.valid?
    assert_includes project.errors[:status], "is not included in the list"
  end

  test "reference is unique per organization but reusable across organizations" do
    create_project(organization: @org, reference: "PRJ-1")
    dup = Project.new(organization: @org, name: "Other", reference: "PRJ-1")
    assert_not dup.valid?

    other_org = create_organization
    assert Project.new(organization: other_org, name: "Other", reference: "PRJ-1").valid?
  end

  test "next_reference increments a suffix to stay unique within the org" do
    first = Project.next_reference(@org)
    create_project(organization: @org, reference: first)
    second = Project.next_reference(@org)

    assert_not_equal first, second
    assert_match(/\APRJ-\d{8}-\d+\z/, first)
  end

  test "buildable? is false for an empty project" do
    assert_not create_project(organization: @org).buildable?
  end

  test "buildable? reflects whether every line is available" do
    project = create_project(organization: @org)
    part = create_part(organization: @org)
    location = create_storage_location(organization: @org)
    StockMovement.create!(organization: @org, part: part, storage_location: location,
      movement_type: "in", quantity_delta: 10)

    line = project.project_lines.create!(part: part, quantity: 4, match_type: "mpn")
    assert project.reload.buildable?

    line.update!(quantity: 20)
    assert_not project.reload.buildable?
    assert_equal [ line ], project.short_lines
  end

  test "unmatched_lines returns lines without a part" do
    project = create_project(organization: @org)
    unmatched = project.project_lines.create!(quantity: 1, match_type: "none")
    project.project_lines.create!(part: create_part(organization: @org), quantity: 1, match_type: "mpn")

    assert_equal [ unmatched ], project.unmatched_lines
  end

  test "a part listed on several lines is judged against its summed requirement" do
    category = create_category(organization: @org)
    location = create_storage_location(organization: @org)
    part = create_part(organization: @org, category: category)
    @org.stock_movements.create!(part: part, storage_location: location, movement_type: "in", quantity_delta: 10)
    project = create_project(organization: @org)
    first = project.project_lines.create!(part: part, quantity: 6, match_type: "mpn")
    second = project.project_lines.create!(part: part, quantity: 6, match_type: "manual")
    project.reload

    assert_equal({ part => 12 }, project.required_by_part)
    assert_equal({ part => 2 }, project.shortfall_by_part)
    assert_not project.buildable?, "each line alone fits in 10, but together they need 12"
    assert_equal [ first, second ].sort_by(&:id), project.short_lines.sort_by(&:id)
  end

  test "buildable? is false while any line is unmatched" do
    project = create_project(organization: @org)
    project.project_lines.create!(part: nil, quantity: 1, match_type: "none", raw_reference: "X")

    assert_not project.buildable?
  end
end

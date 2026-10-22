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

  test "save_with_generated_reference! keeps the BOM lines when it redraws the reference" do
    create_project(organization: @org, reference: "PRJ-TAKEN")
    draws = %w[PRJ-TAKEN PRJ-FREE]
    project = @org.projects.new(name: "Kit")
    project.project_lines.build(quantity: 2, match_type: "none", raw_reference: "X")

    project.save_with_generated_reference! { draws.shift }

    assert_equal "PRJ-FREE", project.reload.reference
    assert_equal 1, project.project_lines.count
  end

  # Stock reservations

  test "reserved_quantities sums the lines of confirmed, reserved projects only" do
    part = create_part(organization: @org)
    reserved = reserving_project({ part => 4 })
    reserved.project_lines.create!(part: part, quantity: 2, match_type: "manual")
    reserving_project({ part => 10 }).update!(status: "draft")
    reserving_project({ part => 7 }).update!(reserved_at: nil)
    other_org = create_organization
    foreign = create_project(organization: other_org, status: "confirmed", reserved_at: Time.current)
    foreign.project_lines.create!(part: create_part(organization: other_org), quantity: 9, match_type: "manual")

    assert_equal({ part.id => 6 }, Project.reserved_quantities(@org))
  end

  test "reserved_quantities is empty when the organization turns reservations off" do
    part = create_part(organization: @org)
    reserving_project({ part => 4 })
    @org.update_column(:stock_reservations_enabled, false)

    assert_equal({}, Project.reserved_quantities(@org))
  end

  test "a project counts reservations made before its own, not after" do
    part = create_part(organization: @org)
    stock(part, 5)
    first = reserving_project({ part => 10 }, reserved_at: 2.hours.ago)
    second = reserving_project({ part => 3 }, reserved_at: 1.hour.ago)
    unreserved = create_project(organization: @org, status: "confirmed")
    unreserved.project_lines.create!(part: part, quantity: 1, match_type: "manual")

    assert_equal({}, first.reserved_elsewhere)
    assert_equal({ part.id => 10 }, second.reserved_elsewhere)
    assert_equal({ part.id => 13 }, unreserved.reserved_elsewhere)

    # Stock never counts below zero, so the two shortfalls add up to what is
    # really missing (13 needed - 5 in stock) instead of ordering it twice.
    assert_equal 5, first.shortfall_by_part[part]
    assert_equal 3, second.shortfall_by_part[part]
  end

  test "another project's reservation can make a project unbuildable" do
    part = create_part(organization: @org)
    stock(part, 10)
    reserving_project({ part => 8 })
    project = create_project(organization: @org, status: "confirmed")
    project.project_lines.create!(part: part, quantity: 5, match_type: "manual")

    assert_equal({ part => 3 }, project.shortfall_by_part)
    assert_not project.buildable?

    @org.update_column(:stock_reservations_enabled, false)
    assert project.reload.buildable?
  end

  test "reserve! only applies to confirmed projects and release_reservation! clears it" do
    draft = create_project(organization: @org)
    draft.reserve!
    assert_nil draft.reserved_at

    project = create_project(organization: @org, status: "confirmed")
    project.reserve!
    assert project.reserving?

    project.release_reservation!
    assert_nil project.reserved_at
    assert_not project.reserving?
  end

  test "kicad_content_type types KiCad files and archives by name, and nothing else" do
    assert_equal Project::KICAD_FILE_TYPE, Project.kicad_content_type("Board.KiCad_Sch")
    assert_equal Project::KICAD_FILE_TYPE, Project.kicad_content_type("libs/fp-lib-table")
    assert_equal Project::ZIP_TYPE, Project.kicad_content_type("board.zip")
    assert_nil Project.kicad_content_type("board.pdf")
    assert_nil Project.kicad_content_type("kicad_sch")
  end

  test "kicad files must be KiCad files or ZIP archives" do
    project = create_project(organization: @org)
    project.kicad_files.attach(io: StringIO.new("<html>"), filename: "board.html", content_type: "text/html")

    assert_not project.valid?
    assert_includes project.errors[:kicad_files].join, "must be a"
  end

  test "replace_bom! keeps hand-picked parts on the same components and drops the review" do
    part = create_part(organization: @org)
    project = create_project(organization: @org, status: "confirmed", reserved_at: Time.current, checked_at: Time.current)
    project.project_lines.create!(part: part, value: "10k", footprint: "R_0603", quantity: 1, match_type: "manual")

    project.replace_bom!([
      { designation: "10k", value: "10K", footprint: "r_0603", designators: "R1, R2", quantity: 2 },
      { designation: "Mystery", value: "MYST", footprint: nil, designators: "U9", quantity: 1 }
    ])

    project.reload
    assert_equal [ "draft", nil, nil ], [ project.status, project.reserved_at, project.checked_at ]
    assert_equal [ [ "10K", part, "manual", 2 ], [ "MYST", nil, "none", 1 ] ],
      project.project_lines.order(:id).map { |l| [ l.value, l.part, l.match_type, l.quantity ] }
  end

  private

  def reserving_project(quantities, reserved_at: Time.current)
    project = create_project(organization: @org, status: "confirmed", reserved_at: reserved_at)
    quantities.each { |part, quantity| project.project_lines.create!(part: part, quantity: quantity, match_type: "manual") }
    project
  end

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: create_storage_location(organization: @org),
                          movement_type: "in", quantity_delta: quantity)
  end
end

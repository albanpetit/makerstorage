require "test_helper"

# Sub-assemblies on the project pages: adding one, building through it, and
# the built item a project puts in stock.
class ProjectAssembliesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @location = create_storage_location(organization: @org)
    @resistor = create_part(organization: @org, name: "Resistor")
    @case = create_part(organization: @org, name: "Case")
    stock(@resistor, 100)
    stock(@case, 5)

    @board = create_project(organization: @org, name: "Driver board", revision: "B", reference: "PRJ-B")
    @board.project_lines.create!(part: @resistor, quantity: 4, match_type: "manual")
    @robot = create_project(organization: @org, name: "Robot", reference: "PRJ-R")
    @robot.project_lines.create!(part: @case, quantity: 1, match_type: "manual")
    sign_in @user
  end

  test "adds another project as a sub-assembly line" do
    assert_difference -> { @robot.project_lines.count } => 1 do
      post project_project_lines_path(@robot), params: { project_line: { subproject_id: @board.id, part_id: @case.id, quantity: 2 } }
    end

    line = @robot.project_lines.order(:id).last
    assert_equal [ @board, nil, "assembly", 2 ], [ line.subproject, line.part, line.match_type, line.quantity ]
    assert_equal [ "Driver board rev B", "PRJ-B" ], [ line.designation, line.raw_reference ]
  end

  test "refuses a sub-assembly that would loop" do
    add_assembly(@robot, @board, 2)

    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(@board), params: { project_line: { subproject_id: @robot.id, quantity: 1 } }
    end
    assert_match(/uses it/, flash[:alert])
  end

  test "refuses another organization's project as a sub-assembly" do
    theirs = create_project(organization: create_organization, name: "Theirs")

    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(@robot), params: { project_line: { subproject_id: theirs.id, quantity: 1 } }
    end
    assert_not ProjectLine.exists?(subproject_id: theirs.id)
  end

  test "picking a part on a sub-assembly line stops using the project" do
    line = add_assembly(@robot, @board, 2)

    patch project_project_line_path(@robot, line), params: { project_line: { part_id: @resistor.id } }
    line.reload
    assert_equal [ nil, @resistor, "manual" ], [ line.subproject, line.part, line.match_type ]
  end

  test "building through a phantom sub-assembly deducts its parts" do
    add_assembly(@robot, @board, 2)

    post build_project_path(@robot), params: { builds_count: 0, kits: 3 }
    assert_match(/deducted/i, flash[:notice])
    assert_equal 100 - 24, @resistor.reload.total_quantity
    assert_equal 2, @case.reload.total_quantity
    assert_equal 0, @board.reload.builds_count
  end

  test "building a project with a built item adds the kits to stock" do
    built = create_part(organization: @org, name: "Driver board (built)")
    @board.update!(output_part: built)

    post build_project_path(@board), params: { builds_count: 0, kits: 2, storage_location_id: @location.id }
    assert_match(/2 × Driver board \(built\) added to stock/, flash[:notice])
    assert_equal 2, built.reload.total_quantity
    assert_equal 92, @resistor.reload.total_quantity
    build = @board.project_builds.sole
    assert_equal [ -8, 2 ], build.stock_movements.order(:id).pluck(:quantity_delta)

    # The history counts what the build took, not what it made.
    get project_path(@board)
    assert_equal [ 8, 1 ], inertia_props["project"]["builds"].first.values_at("units", "references")
  end

  test "a build with a built item that has no zone yet needs one" do
    @board.update!(output_part: create_part(organization: @org, name: "Driver board (built)"))

    assert_no_difference -> { StockMovement.count } do
      post build_project_path(@board), params: { builds_count: 0 }
    end
    assert_match(/no storage zone yet/, flash[:alert])
  end

  test "a stocked sub-assembly is taken from stock by the parent build" do
    built = create_part(organization: @org, name: "Driver board (built)")
    @board.update!(output_part: built)
    add_assembly(@robot, @board, 2)

    post build_project_path(@robot), params: { builds_count: 0 }
    assert_match(/isn't buildable/, flash[:alert])

    post build_project_path(@board), params: { builds_count: 0, kits: 2, storage_location_id: @location.id }
    post build_project_path(@robot), params: { builds_count: 0 }
    assert_match(/deducted/i, flash[:notice])
    assert_equal 0, built.reload.total_quantity
    assert_equal 92, @resistor.reload.total_quantity
  end

  test "edits the built item" do
    built = create_part(organization: @org, name: "Driver board (built)")
    patch project_path(@board), params: { project: { output_part_id: built.id } }
    assert_equal built, @board.reload.output_part

    patch project_path(@board), params: { project: { output_part_id: "" } }
    assert_nil @board.reload.output_part
  end

  test "the page shows sub-assembly lines, the parts they bring and where the project is used" do
    line = add_assembly(@robot, @board, 2)

    get project_path(@robot)
    project = inertia_props["project"]
    assembly = project["lines"].find { |entry| entry["id"] == line.id }
    assert_equal({ "id" => @board.id, "name" => "Driver board", "reference" => "PRJ-B", "revision" => "B", "stocked" => false,
                   "output_part" => nil, "complete" => true, "parts_count" => 1, "short_parts" => 0 }, assembly["assembly"])
    assert assembly["available"]
    assert_equal [ [ "Resistor", 8, 100 ] ], project["assembly_parts"].map { |entry| [ entry["part"]["name"], entry["quantity"], entry["in_stock"] ] }
    assert project["buildable"]
    assert_equal [ "Driver board" ], inertia_props["subproject_options"].map { |option| option["name"] }

    get project_path(@board)
    assert_equal [ [ "Robot", 2 ] ], inertia_props["project"]["used_in"].map { |entry| entry.values_at("name", "quantity") }
    # The robot uses the board: it can't become one of the board's sub-assemblies.
    assert_empty inertia_props["subproject_options"]
  end

  test "the projects list counts sub-assemblies" do
    add_assembly(@robot, @board, 2)

    get projects_path
    robot = inertia_props["projects"].find { |entry| entry["id"] == @robot.id }
    board = inertia_props["projects"].find { |entry| entry["id"] == @board.id }
    assert_equal [ 1, true, false ], robot.values_at("assembly_count", "buildable", "used_as_assembly")
    assert_equal [ 0, true ], board.values_at("assembly_count", "used_as_assembly")
  end

  test "a part's reservations include the projects holding it through a sub-assembly" do
    @org.update!(stock_reservations_enabled: true)
    add_assembly(@robot, @board, 2)
    @robot.update!(status: "confirmed", reserved_at: Time.current)

    get part_path(@resistor), headers: { "Accept" => "application/json" }
    assert_equal [ [ "Robot", 8 ] ], JSON.parse(response.body)["reservations"].map { |entry| entry.values_at("name", "quantity") }
  end

  private

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @location, movement_type: "in", quantity_delta: quantity)
  end

  def add_assembly(project, subproject, quantity)
    project.project_lines.create!(subproject: subproject, quantity: quantity, match_type: "assembly", designation: subproject.name)
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

require "test_helper"

# Projects using other projects as sub-assemblies (ProjectLine#subproject,
# Project#output_part, ProjectStructure).
class ProjectAssemblyTest < ActiveSupport::TestCase
  setup do
    @org = create_organization(stock_reservations_enabled: true)
    @location = create_storage_location(organization: @org)
    @resistor = create_part(organization: @org, name: "Resistor")
    @led = create_part(organization: @org, name: "LED")
    @case = create_part(organization: @org, name: "Case")
    stock(@resistor, 100)
    stock(@led, 10)
    stock(@case, 5)

    # Driver board: 4 resistors + 2 LEDs. Robot: 2 driver boards + 1 case.
    @board = create_project(organization: @org, name: "Driver board")
    add_line(@board, @resistor, 4)
    add_line(@board, @led, 2)
    @robot = create_project(organization: @org, name: "Robot")
    add_line(@robot, @case, 1)
    add_assembly(@robot, @board, 2)
  end

  test "a phantom sub-assembly brings its parts, times the line quantity" do
    required = @robot.required_by_part.transform_keys(&:name)
    assert_equal({ "Case" => 1, "Resistor" => 8, "LED" => 4 }, required)
    assert_equal({ "Case" => 3, "Resistor" => 24, "LED" => 12 }, @robot.required_by_part(kits: 3).transform_keys(&:name))
  end

  test "a part on a line and in a sub-assembly is summed" do
    add_line(@robot, @led, 1)
    assert_equal 5, reloaded(@robot).required_by_part[@led]
  end

  test "sub-assemblies expand through several levels" do
    fleet = create_project(organization: @org, name: "Fleet")
    add_assembly(fleet, @robot, 3)
    assert_equal({ "Case" => 3, "Resistor" => 24, "LED" => 12 }, reloaded(fleet).required_by_part.transform_keys(&:name))
  end

  test "a stocked sub-assembly is taken from stock as its built item" do
    built_board = create_part(organization: @org, name: "Driver board (built)")
    @board.update!(output_part: built_board)

    assert_equal({ "Case" => 1, "Driver board (built)" => 2 }, reloaded(@robot).required_by_part.transform_keys(&:name))
  end

  test "buildability follows the sub-assembly's parts" do
    assert reloaded(@robot).buildable?
    assert reloaded(@robot).buildable?(kits: 2)
    # 3 kits need 12 LEDs, 10 in stock.
    refute reloaded(@robot).buildable?(kits: 3)
    robot = reloaded(@robot)
    assert_equal({ @led => 2 }, robot.shortfall_by_part(kits: 3))
  end

  test "a sub-assembly line bringing a short part is a short line" do
    add_line(@board, @led, 20)
    robot = reloaded(@robot)
    assert_equal [ robot.project_lines.find(&:assembly?) ], robot.short_lines
    refute robot.buildable?
  end

  test "an incomplete phantom sub-assembly blocks the build without counting as unmatched" do
    @board.project_lines.create!(designation: "Mystery IC", quantity: 1, match_type: "none")
    robot = reloaded(@robot)
    assert_empty robot.unmatched_lines
    assert_equal 1, robot.incomplete_assembly_lines.size
    refute robot.buildable?

    empty = create_project(organization: @org, name: "Empty")
    other = create_project(organization: @org, name: "Other")
    add_assembly(other, empty, 1)
    assert_equal 1, reloaded(other).incomplete_assembly_lines.size
  end

  test "a stocked sub-assembly is complete whatever its own lines" do
    @board.project_lines.create!(designation: "Mystery IC", quantity: 1, match_type: "none")
    @board.update!(output_part: create_part(organization: @org, name: "Built board"))
    assert_empty reloaded(@robot).incomplete_assembly_lines
  end

  test "reservations hold the sub-assemblies' parts" do
    @robot.update!(status: "confirmed", reserved_at: 1.hour.ago)
    assert_equal({ @case.id => 1, @resistor.id => 8, @led.id => 4 }, Project.reserved_quantities(@org))
    assert_equal({ @led.id => 4 }, Project.reserved_quantities(@org, part_ids: [ @led.id ]))
    assert_equal [ [ @robot, 4 ] ], Project.reservations_of(@org, @led)

    # A later project sees what the robot holds.
    lamp = create_project(organization: @org, name: "Lamp")
    add_line(lamp, @led, 8)
    lamp = reloaded(lamp)
    assert_equal 4, lamp.reserved_elsewhere[@led.id]
    assert_equal({ @led => 2 }, lamp.shortfall_by_part)
  end

  test "a line can't use its own project, or one that uses it" do
    line = @board.project_lines.new(subproject: @board, quantity: 1, match_type: "assembly")
    refute line.valid?
    assert line.errors.added?(:subproject, :assembly_loop)

    line = @board.project_lines.new(subproject: @robot, quantity: 1, match_type: "assembly")
    refute line.valid?
    assert line.errors.added?(:subproject, :assembly_loop)
  end

  test "a line can't use another organization's project, nor a part and a project at once" do
    other = create_project(organization: create_organization, name: "Theirs")
    line = @robot.project_lines.new(subproject: other, quantity: 1, match_type: "assembly")
    refute line.valid?
    assert line.errors.added?(:subproject, :same_organization)

    line = @robot.project_lines.new(subproject: @board, part: @case, quantity: 1, match_type: "assembly")
    refute line.valid?
    assert line.errors.added?(:subproject, :part_or_subproject)
  end

  test "sub-assemblies can't nest deeper than the limit" do
    chain = [ @board ]
    (ProjectStructure::MAX_DEPTH - 1).times do |index|
      parent = create_project(organization: @org, name: "Level #{index}")
      add_assembly(parent, chain.last, 1)
      chain << parent
    end
    # @board is under MAX_DEPTH - 1 levels; one more is still fine, a second isn't.
    top = create_project(organization: @org, name: "Top")
    add_assembly(top, chain.last, 1)
    too_deep = create_project(organization: @org, name: "Too deep")
    line = too_deep.project_lines.new(subproject: top, quantity: 1, match_type: "assembly")
    refute line.valid?
    assert line.errors.added?(:subproject, :assembly_too_deep, count: ProjectStructure::MAX_DEPTH)
  end

  test "the built item must belong to the organization" do
    @board.output_part = create_part(organization: create_organization)
    refute @board.valid?
    assert @board.errors.added?(:output_part, :same_organization)
  end

  test "deleting a sub-assembly's project leaves a free-text line in its parents" do
    line = @robot.project_lines.find(&:assembly?)
    @board.destroy!
    line.reload
    assert_nil line.subproject_id
    assert_equal "none", line.match_type
    assert_equal "Driver board", line.designation
    assert_equal 1, reloaded(@robot).unmatched_lines.size
  end

  test "deleting the built item's part leaves the project without one" do
    built = create_part(organization: @org, name: "Built board")
    @board.update!(output_part: built)
    built.destroy!
    assert_nil @board.reload.output_part_id
  end

  test "a new revision keeps the sub-assemblies and the built item" do
    built = create_part(organization: @org, name: "Built robot")
    @robot.update!(output_part: built, reference: "PRJ-1")
    copy = @robot.duplicate_as_revision
    copy.save_with_generated_reference! { Project.next_reference(@org) }
    assert_equal built, copy.output_part
    assert_equal [ @board.id ], copy.project_lines.filter_map(&:subproject_id)
  end

  test "the structure lists descendants, ancestors and depths" do
    fleet = create_project(organization: @org, name: "Fleet")
    add_assembly(fleet, @robot, 1)
    assert_equal Set[@robot.id, @board.id], ProjectStructure.descendant_ids(fleet.id)
    assert_equal Set[@robot.id, fleet.id], ProjectStructure.ancestor_ids(@board.id)
    assert_equal 2, ProjectStructure.depth_below(fleet.id)
    assert_equal 2, ProjectStructure.depth_above(@board.id)
    assert_equal 0, ProjectStructure.depth_below(@board.id)
  end

  test "a shared structure gives each project its own requirements" do
    structure = ProjectStructure.new(@org)
    assert_equal({ @resistor.id => 4, @led.id => 2 }, structure.part_quantities(@board.id))
    assert_equal({ @case.id => 1, @resistor.id => 8, @led.id => 4 }, structure.part_quantities(@robot.id))
  end

  private

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @location, movement_type: "in", quantity_delta: quantity)
  end

  def add_line(project, part, quantity)
    project.project_lines.create!(part: part, quantity: quantity, match_type: "manual")
  end

  def add_assembly(project, subproject, quantity)
    project.project_lines.create!(subproject: subproject, quantity: quantity, match_type: "assembly", designation: subproject.name)
  end

  def reloaded(project)
    Project.includes(project_lines: { part: :part_storages }).find(project.id)
  end
end

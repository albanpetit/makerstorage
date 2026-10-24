require "test_helper"

class McpServerWriteToolsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org, name: "Resistors")
    @footprint = create_footprint(organization: @org, name: "R_0603_1608Metric")
    @drawer = create_storage_location(organization: @org, name: "Drawer A", location_type: "drawer", code: "DA")
    @shelf = create_storage_location(organization: @org, name: "Shelf B", location_type: "shelf", code: "SB")
    @part = create_part(organization: @org, category: @category, name: "Resistor 10k", value: "10k", mpn: "RC0603-10K", footprint: @footprint)
    stock(@part, 30, @drawer)

    @other = create_organization
    @other_zone = create_storage_location(organization: @other, name: "Their drawer", code: "TD")
    @other_part = create_part(organization: @other, name: "Theirs", mpn: "THEIRS")

    @server = McpServer.new(organization: @org, base_url: "https://stock.example", user: @user, client_name: "Claude", write: true)
  end

  test "write tools are listed and callable only on a write grant" do
    assert_equal McpServer::Tools.names + McpServer::WriteTools.names, tool_names(@server)
    assert McpServer::WriteTools.definitions.none? { |tool| tool.dig(:annotations, :readOnlyHint) }

    read_only = McpServer.new(organization: @org, base_url: "https://stock.example", user: @user, client_name: "Claude")
    assert_equal McpServer::Tools.names, tool_names(read_only)
    assert_match "Nothing here can change", read_only.handle(rpc_message("initialize"))[:result][:instructions]

    result = read_only.handle(rpc_message("tools/call", name: "record_stock_movement", arguments: { part_id: @part.id, direction: "out", quantity: 1 }))[:result]
    assert result[:isError]
    assert_match "read-only", result[:content].first[:text]
    assert_equal 30, @part.reload.total_quantity
  end

  test "record_stock_movement takes stock out and puts it in, signed by the user and the client" do
    data = call("record_stock_movement", "part" => "rc0603-10k", "direction" => "out", "quantity" => 4, "reason" => "Workshop")

    assert_equal 26, data[:on_hand]
    assert_equal({ id: @drawer.id, path: "Drawer A", code: "DA", quantity: 26 }, data[:location])
    movement = @org.stock_movements.order(:id).last
    assert_equal [ "out", -4, @user, "Workshop (via Claude)" ], [ movement.movement_type, movement.quantity_delta, movement.user, movement.reason ]

    data = call("record_stock_movement", "part_id" => @part.id, "direction" => "in", "quantity" => 10, "location" => "sb")
    assert_equal 36, data[:on_hand]
    assert_equal 10, data.dig(:location, :quantity)
    assert_equal "Stock added (via Claude)", @org.stock_movements.order(:id).last.reason

    # No location: in goes where the part was first stocked.
    assert_equal "Drawer A", call("record_stock_movement", "part_id" => @part.id, "direction" => "in", "quantity" => 1).dig(:location, :path)
  end

  test "stock tools take decimals for a part counted in a measure, whole numbers otherwise" do
    wire = create_part(organization: @org, category: @category, name: "Hookup wire", mpn: "WIRE-22", unit: "meter")
    stock(wire, 10, @drawer)

    data = call("record_stock_movement", "part" => "WIRE-22", "direction" => "out", "quantity" => 2.5)
    assert_equal 7.5, data[:on_hand]
    assert_equal 6.25, call("set_stock_count", "part" => "WIRE-22", "counted_quantity" => "6,25")[:on_hand]

    error = assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "out", "quantity" => 1.5) }
    assert_match "whole number", error.message

    created = call("create_part", "name" => "PLA filament", "category" => "Resistors", "unit" => "gram", "pack_size" => 1000,
                   "initial_quantity" => 750.5, "location" => "SB")
    part = @org.parts.find(created[:id])
    assert_equal [ "gram", 1000, 750.5 ], [ part.unit, part.pack_size, part.total_quantity ]
  end

  test "record_stock_movement refuses overdraws, unclear locations and other organizations' records" do
    error = assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "out", "quantity" => 31) }
    assert_match "negative", error.message.downcase

    stock(@part, 5, @shelf)
    error = assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "out", "quantity" => 1) }
    assert_match "several places", error.message

    assert_raises_tool_error { call("record_stock_movement", "part_id" => @other_part.id, "direction" => "in", "quantity" => 1, "location" => "DA") }
    assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "in", "quantity" => 1, "location_id" => @other_zone.id) }
    assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "sideways", "quantity" => 1) }
    assert_raises_tool_error { call("record_stock_movement", "part_id" => @part.id, "direction" => "in", "quantity" => 0) }
    assert_equal 35, @part.reload.total_quantity
  end

  test "move_stock moves everything by default, or a quantity, in one go" do
    data = call("move_stock", "part_id" => @part.id, "to_location" => "Shelf B", "quantity" => 10)
    assert_equal [ 10, 30 ], [ data.dig(:location, :quantity), data[:on_hand] ]
    assert_equal 20, data.dig(:from, :quantity)
    assert_equal [ "Moved to Shelf B (via Claude)", "Moved from Drawer A (via Claude)" ], data[:movements].map { |movement| movement[:reason] }

    data = call("move_stock", "part_id" => @part.id, "from_location" => "DA", "to_location" => "SB")
    assert_equal [ 30, 0 ], [ data.dig(:location, :quantity), data.dig(:from, :quantity) ]

    assert_raises_tool_error { call("move_stock", "part_id" => @part.id, "from_location" => "SB", "to_location" => "DA", "quantity" => 31) }
    assert_raises_tool_error { call("move_stock", "part_id" => @part.id, "from_location" => "SB", "to_location" => "SB") }
    assert_equal 30, PartStorage.find_by(part: @part, storage_location: @shelf).quantity
  end

  test "set_stock_count writes the difference as an adjustment, nothing when it matches" do
    data = call("set_stock_count", "part_id" => @part.id, "counted_quantity" => 27)
    assert_equal 27, data[:on_hand]
    movement = @org.stock_movements.order(:id).last
    assert_equal [ "adjustment", -3, "Counted 27 (via Claude)" ], [ movement.movement_type, movement.quantity_delta, movement.reason ]

    assert_no_difference -> { StockMovement.count } do
      assert call("set_stock_count", "part_id" => @part.id, "location" => "DA", "counted_quantity" => 27)[:unchanged]
    end
  end

  test "create_part creates a part with its opening stock" do
    data = call("create_part", "name" => "Resistor 4k7", "value" => "4.7k", "category" => "resistors", "footprint" => "r_0603_1608metric",
                               "mpn" => "RC0603-4K7", "min_stock_threshold" => 20, "unit_price" => 0.01,
                               "initial_quantity" => 50, "location" => "SB")

    part = @org.parts.find(data[:id])
    assert data[:created]
    assert_equal [ "Resistor 4k7", "4.7k", @category, @footprint, 20, 50 ],
                 [ part.name, part.value, part.category, part.footprint, part.min_stock_threshold, part.total_quantity ]
    assert_equal "Initial stock (via Claude)", part.stock_movements.sole.reason

    error = assert_raises_tool_error { call("create_part", "name" => "Copy", "category" => "Resistors", "mpn" => "RC0603-10K") }
    assert_match "Mpn", error.message
    assert_raises_tool_error { call("create_part", "name" => "Unknown category", "category" => "Nope") }
    assert_raises_tool_error { call("create_part", "name" => "No category") }
    assert_raises_tool_error { call("create_part", "name" => "No location", "category" => "Resistors", "initial_quantity" => 3) }
  end

  test "create_part in box & bag numbering takes the bag its opening stock goes into" do
    @org.update!(ipn_generation_mode: "box_bag")
    box = create_storage_location(organization: @org, name: "Box", location_type: "box", code: "A")
    bag = box.add_bags!(2).last

    data = call("create_part", "name" => "Capacitor 100n", "category" => "Resistors", "initial_quantity" => 10, "location_id" => bag.id)
    assert_equal bag.code, data[:ipn]
    assert_equal bag, @org.parts.find(data[:id]).bag
  end

  test "create_part rolls the part back when the opening stock is refused" do
    @org.update!(ipn_generation_mode: "box_bag")
    box = create_storage_location(organization: @org, name: "Box", location_type: "box", code: "A")
    bag = box.add_bags!(1).first
    create_part(organization: @org, name: "Occupant", bag: bag)

    assert_no_difference -> { @org.parts.count } do
      error = assert_raises_tool_error { call("create_part", "name" => "Intruder", "category" => "Resistors", "initial_quantity" => 1, "location_id" => bag.id) }
      assert_match "already holding another part", error.message
    end
  end

  test "update_part changes only the given fields" do
    data = call("update_part", "part" => "RC0603-10K", "description" => "Thick film", "tolerance" => "1%", "status" => "discontinued")

    assert_equal({ from: nil, to: "Thick film" }, data[:changes]["description"])
    @part.reload
    assert_equal [ "Thick film", "1%", "discontinued", "10k" ], [ @part.description, @part.tolerance, @part.status, @part.value ]

    call("update_part", "part_id" => @part.id, "description" => "")
    assert_nil @part.reload.description

    assert_raises_tool_error { call("update_part", "part_id" => @part.id) }
    assert_raises_tool_error { call("update_part", "part_id" => @part.id, "name" => "") }
    assert_raises_tool_error { call("update_part", "part_id" => @other_part.id, "name" => "Hijacked") }
    assert_equal "Theirs", @other_part.reload.name
  end

  test "create_project matches the lines and answers like get_project" do
    data = call("create_project", "name" => "LED badge", "revision" => "v1", "lines" => [
      { "designators" => "R1, R2", "value" => "10k", "footprint" => "0603", "quantity" => 2 },
      { "mpn" => "NE555", "quantity" => 1 }
    ])

    project = @org.projects.find(data[:id])
    assert data[:created]
    assert_equal [ "LED badge", "v1", "draft" ], [ project.name, project.revision, project.status ]
    assert_match(/\APRJ-/, project.reference)
    assert_equal [ "ok", "unmatched" ], data[:lines].map { |line| line[:status] }
    assert_equal @part.id, data[:lines].first.dig(:part, :id)
    assert_equal [ @part, nil ], project.project_lines.order(:id).map(&:part)

    assert_raises_tool_error { call("create_project", "name" => "Empty", "lines" => []) }
  end

  test "a write grant still can't reach the read-only server's unknown tools" do
    assert_equal McpServer::INVALID_PARAMS, @server.handle(rpc_message("tools/call", name: "delete_everything")).dig(:error, :code)
  end

  private

  def stock(part, quantity, location)
    StockMovement.create!(organization: part.organization, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  def tool_names(server)
    server.handle(rpc_message("tools/list"))[:result][:tools].map { |tool| tool[:name] }
  end

  def rpc_message(method, **params)
    { "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params.deep_stringify_keys }
  end

  def call(name, arguments)
    McpServer::WriteTools.new(organization: @org, base_url: "https://stock.example", user: @user, client_name: "Claude").call(name, arguments)
  end

  def assert_raises_tool_error(&block)
    assert_raises(McpServer::Tools::ToolError, &block)
  end
end

require "test_helper"

class McpServerTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org, name: "Resistors")
    @footprint_0603 = create_footprint(organization: @org, name: "R_0603_1608Metric")
    @footprint_0805 = create_footprint(organization: @org, name: "R_0805_2012Metric")
    @drawer = create_storage_location(organization: @org, name: "Drawer A", location_type: "drawer", code: "DA")
    @box = create_storage_location(organization: @org, name: "Box 1", location_type: "box", parent: @drawer, code: "B1")

    @r10k = create_part(organization: @org, category: @category, name: "Resistor 10k 0603", value: "10k",
                        footprint: @footprint_0603, mpn: "RC0603FR-0710KL", tolerance: "1%")
    @r10k_0805 = create_part(organization: @org, category: @category, name: "Resistor 10k 0805", value: "10k", footprint: @footprint_0805)
    @r4k7 = create_part(organization: @org, category: @category, name: "Resistor 4k7", value: "4.7k", footprint: @footprint_0603, min_stock_threshold: 50)
    stock(@r10k, 30, @box)
    stock(@r10k_0805, 8, @drawer)
    stock(@r4k7, 4, @drawer)

    # Another organization's data must never show up.
    other = create_organization
    create_part(organization: other, name: "Resistor 10k secret", value: "10k", mpn: "SECRET-10K")

    @server = McpServer.new(organization: @org, base_url: "https://stock.example")
  end

  test "initialize negotiates the protocol version and announces tools" do
    result = rpc("initialize", protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test" })
    assert_equal "2025-06-18", result["protocolVersion"]
    assert result.dig("capabilities", "tools")
    assert_match @org.name, result["instructions"]

    assert_equal McpServer::PROTOCOL_VERSIONS.first, rpc("initialize", protocolVersion: "1999-01-01")["protocolVersion"]
  end

  test "lists read-only tools" do
    tools = rpc("tools/list")["tools"]
    assert_equal McpServer::Tools.names, tools.map { |tool| tool[:name] }
    assert tools.all? { |tool| tool.dig(:annotations, :readOnlyHint) && tool[:inputSchema][:type] == "object" }
  end

  test "notifications get no reply; unknown methods and malformed messages get errors" do
    assert_nil @server.handle({ "jsonrpc" => "2.0", "method" => "notifications/initialized" })
    assert_equal McpServer::METHOD_NOT_FOUND, @server.handle(rpc_message("resources/list")).dig(:error, :code)
    assert_equal McpServer::INVALID_REQUEST, @server.handle({ "id" => 1 }).dig(:error, :code)
    assert_equal McpServer::INVALID_PARAMS, @server.handle(rpc_message("tools/call", name: "delete_everything")).dig(:error, :code)
  end

  test "search_parts finds parts by text, value and package, with stock and locations" do
    data = call("search_parts", "query" => "10k")
    assert_equal [ @r10k.id, @r10k_0805.id ], data[:parts].map { |part| part[:id] }

    data = call("search_parts", "value" => "10000", "package" => "0603")
    assert_equal [], data[:parts], "10000 isn't normalized to 10k"

    data = call("search_parts", "value" => "10K", "package" => "0603")
    part = data[:parts].sole
    assert_equal @r10k.id, part[:id]
    assert_equal({ on_hand: 30, reserved: 0, available: 30, incoming: 0, min_stock_threshold: 0, low_stock: false }, part[:stock])
    assert_equal [ { path: "Drawer A > Box 1", code: "B1", quantity: 30 } ], part[:locations]
    assert_equal "https://stock.example/parts/#{@r10k.id}", part[:url]
    assert_equal "Resistors", part[:category]

    assert_equal [ @r4k7.id ], call("search_parts", "value" => "4k7")[:parts].map { |p| p[:id] }
    assert_equal 1, call("search_parts", "query" => "Resistor", "limit" => 1)[:parts].size
    assert call("search_parts", "query" => "Resistor", "limit" => 1)[:truncated]
  end

  test "search_parts never returns another organization's parts" do
    assert_empty call("search_parts", "query" => "SECRET")[:parts]
    assert_raises_tool_error { call("get_part", "reference" => "SECRET-10K") }
  end

  test "search_parts can keep only parts available after reservations" do
    project = create_project(organization: @org, status: "confirmed", reserved_at: Time.current)
    ProjectLine.create!(project: project, part: @r4k7, quantity: 4, match_type: "manual")

    ids = call("search_parts", "query" => "Resistor", "in_stock_only" => true)[:parts].map { |part| part[:id] }
    assert_not_includes ids, @r4k7.id
    assert_includes ids, @r10k.id
  end

  test "get_part details suppliers, open orders, reservations and projects" do
    supplier = create_supplier(organization: @org, name: "LCSC")
    PartSupplier.create!(part: @r10k, supplier: supplier, supplier_sku: "C25804", unit_price: 0.01, is_preferred: true)
    order = create_order(organization: @org, supplier: supplier, expected_delivery: Date.new(2026, 11, 1))
    OrderLine.create!(order: order, part: @r10k, quantity: 100)
    project = create_project(organization: @org, name: "Clock", status: "confirmed", reserved_at: Time.current)
    ProjectLine.create!(project: project, part: @r10k, quantity: 12, match_type: "mpn")

    data = call("get_part", "reference" => "rc0603fr-0710kl")
    assert_equal @r10k.id, data[:id]
    assert_equal({ on_hand: 30, reserved: 12, available: 18, incoming: 100, min_stock_threshold: 0, low_stock: false }, data[:stock])
    assert_equal "C25804", data[:suppliers].sole[:supplier_sku]
    assert_equal 100, data[:open_orders].sole[:quantity]
    assert_equal "2026-11-01", data[:open_orders].sole[:expected_delivery]
    assert_equal [ { project_id: project.id, project: "Clock", reference: nil, quantity: 12 } ], data[:reserved_by]
    assert_equal "Clock", data[:used_in_projects].sole[:name]

    assert_equal @r10k.id, call("get_part", "id" => @r10k.id)[:id]
    assert_raises_tool_error { call("get_part", {}) }
  end

  test "check_bom matches lines, reports shortfalls and how many builds fit" do
    data = call("check_bom", "builds" => 2, "lines" => [
      { "designators" => "R1-R5", "value" => "10k", "footprint" => "Resistor_SMD:R_0603_1608Metric", "quantity" => 5 },
      { "designators" => "R6", "value" => "4k7", "footprint" => "0603", "quantity" => 3 },
      { "designators" => "U1", "mpn" => "ATMEGA328P-AU", "quantity" => 1 },
      { "designators" => "R7", "value" => "10k", "footprint" => "1206", "quantity" => 1 }
    ])

    assert_equal false, data[:buildable]
    assert_nil data[:max_builds]
    assert_equal({ lines: 4, ok: 1, short: 1, unmatched: 2 }, data[:summary])

    r1, r6, u1, r7 = data[:lines]
    assert_equal [ "ok", "value_footprint", @r10k.id, 10, 0 ], [ r1[:status], r1[:match_type], r1[:part][:id], r1[:part_required_total], r1[:missing] ]
    assert_equal [ "short", 6, 4, 2 ], [ r6[:status], r6[:part_required_total], r6[:available], r6[:missing] ]
    assert_equal "unmatched", u1[:status]
    assert_equal "R7", r7["designators"]
    assert_equal [ @r10k.id, @r10k_0805.id ].sort, r7[:similar_parts].map { |part| part[:id] }.sort

    data = call("check_bom", "lines" => [ { "mpn" => "RC0603FR-0710KL", "quantity" => 4 }, { "value" => "10k", "footprint" => "0603", "quantity" => 3 } ])
    assert data[:buildable]
    assert_equal 4, data[:max_builds], "both lines use the same part: 7 per build out of 30"
  end

  test "check_bom validates its input" do
    assert_raises_tool_error { call("check_bom", "lines" => []) }
    assert_raises_tool_error { call("check_bom", "lines" => [ "R1" ]) }
    assert_raises_tool_error { call("check_bom", "lines" => [ { "value" => "10k", "quantity" => 0 } ]) }
    assert_raises_tool_error { call("check_bom", "lines" => [ { "value" => "10k" } ], "builds" => "lots") }
  end

  test "list_projects and get_project report availability per build" do
    project = create_project(organization: @org, name: "Blinky", reference: "PRJ-1", status: "confirmed")
    ProjectLine.create!(project: project, part: @r10k, quantity: 10, match_type: "mpn", designators: "R1-R10")
    ProjectLine.create!(project: project, part: @r4k7, quantity: 2, match_type: "value_footprint")

    listed = call("list_projects", {})[:projects].sole
    assert_equal [ "Blinky", true, 0 ], [ listed[:name], listed[:buildable], listed[:short_parts] ]
    assert_empty call("list_projects", "status" => "draft")[:projects]

    data = call("get_project", "reference" => "prj-1", "builds" => 3)
    assert_equal false, data[:buildable]
    assert_equal 2, data[:max_builds]
    r1, r2 = data[:lines]
    assert_equal [ "ok", 30, 0 ], [ r1[:status], r1[:part_required_total], r1[:missing] ]
    assert_equal [ "short", 6, 2 ], [ r2[:status], r2[:part_required_total], r2[:missing] ]

    assert_equal project.id, call("get_project", "reference" => "blinky")[:id]
    assert_raises_tool_error { call("get_project", "id" => -1) }
  end

  test "list_loans reports open and overdue loans with what is still out" do
    @org.update!(timezone: "Etc/UTC")
    late = @org.loans.new(borrower_name: "Ada Lovelace", due_on: @org.local_date - 3)
    late.loan_lines.build(part: @r10k, storage_location: @box, quantity: 2)
    late.lend!(user: @user)
    back = @org.loans.new(borrower_name: "Bob")
    back.loan_lines.build(part: @r4k7, storage_location: @drawer, quantity: 1)
    back.lend!(user: @user).return_all!(user: @user)

    listed = call("list_loans", {})[:loans].sole
    assert_equal [ late.id, "overdue", 3 ], [ listed[:id], listed[:status], listed[:days_overdue] ]
    assert_equal [ [ @r10k.id, 2, 2 ] ], listed[:items].map { |item| [ item[:part][:id], item[:quantity], item[:outstanding] ] }
    assert_equal [ late.id ], call("list_loans", "status" => "overdue", "borrower" => "lovelace")[:loans].map { |loan| loan[:id] }
    assert_equal [ back.id ], call("list_loans", "status" => "returned")[:loans].map { |loan| loan[:id] }
    assert_empty call("list_loans", "borrower" => "nobody")[:loans]
    assert_raises_tool_error { call("list_loans", "status" => "lost") }
  end

  test "get_storage_location lists sub-zones and the parts stored below" do
    data = call("get_storage_location", "code" => "da")
    assert_equal "Drawer A", data[:path]
    assert_equal [ "Box 1" ], data[:sub_zones].map { |zone| zone[:name] }
    assert_equal [ [ @r10k.id, 30, "Drawer A > Box 1" ], [ @r10k_0805.id, 8, "Drawer A" ], [ @r4k7.id, 4, "Drawer A" ] ].sort,
      data[:parts].map { |part| [ part[:id], part[:quantity], part[:location] ] }.sort
  end

  test "inventory_overview lists vocabulary and low stock" do
    data = call("inventory_overview", {})
    assert_equal 3, data[:counts][:parts]
    assert_includes data[:categories], "Resistors"
    assert_includes data[:footprints], "R_0603_1608Metric"
    assert_equal [ { id: @r4k7.id, ipn: @r4k7.ipn, name: "Resistor 4k7", on_hand: 4, min_stock_threshold: 50 } ], data[:low_stock_parts]
  end

  test "tool errors come back as results the model can read" do
    result = rpc("tools/call", name: "get_part", arguments: { reference: "nothing" })
    assert result[:isError]
    assert_match(/No part/, result[:content].first[:text])

    result = rpc("tools/call", name: "inventory_overview")
    assert_equal false, result[:isError]
    assert_equal result[:structuredContent].as_json, JSON.parse(result[:content].first[:text])
  end

  test "get_part lists the part's parameters in their canonical form" do
    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    @r4k7.update!(parameter_values: { resistance.id => "4k7" })

    assert_equal({ "Resistance" => "4.7 kΩ" }, call("get_part", "id" => @r4k7.id)[:parameters])
  end

  private

  def stock(part, quantity, location)
    StockMovement.create!(organization: @org, part: part, storage_location: location, movement_type: "in", quantity_delta: quantity)
  end

  def rpc_message(method, **params)
    { "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params.deep_stringify_keys }
  end

  def rpc(method, **params)
    response = @server.handle(rpc_message(method, **params))
    assert_nil response[:error], response[:error].inspect
    result = response[:result]
    result.is_a?(Hash) ? result.with_indifferent_access : result
  end

  def call(name, arguments)
    McpServer::Tools.new(organization: @org, base_url: "https://stock.example").call(name, arguments)
  end

  def assert_raises_tool_error(&block)
    assert_raises(McpServer::Tools::ToolError, &block)
  end
end

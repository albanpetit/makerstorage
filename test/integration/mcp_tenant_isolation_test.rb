require "test_helper"

# Every MCP tool, called by a writer of another organization with the
# victim's ids, references and codes in every argument: nothing of the victim
# may come back, and nothing of theirs may change. Tools are listed from the
# server, so a new tool is covered without touching this test. (The route
# sweep in tenant_isolation_test.rb doesn't reach MCP: it takes a bearer token.)
class McpTenantIsolationTest < ActiveSupport::TestCase
  CANARY = "CANARYZZQX".freeze

  VICTIM_TABLES = {
    "parts" => "SELECT * FROM parts WHERE organization_id = :org",
    "part_storages" => "SELECT * FROM part_storages WHERE part_id IN (SELECT id FROM parts WHERE organization_id = :org)",
    "stock_movements" => "SELECT * FROM stock_movements WHERE organization_id = :org",
    "projects" => "SELECT * FROM projects WHERE organization_id = :org",
    "project_lines" => "SELECT * FROM project_lines WHERE project_id IN (SELECT id FROM projects WHERE organization_id = :org)",
    "storage_locations" => "SELECT * FROM storage_locations WHERE organization_id = :org",
    "orders" => "SELECT * FROM orders WHERE organization_id = :org",
    "loans" => "SELECT * FROM loans WHERE organization_id = :org"
  }.freeze

  setup do
    @owner = create_user(email: "victim@example.com")
    @victim = OrganizationDemo.new(@owner).create!
    @victim.update!(name: "Org #{CANARY}")
    @part = @victim.parts.where.not(ipn: nil).first
    # The MPN is used as an argument, so it must not hold the canary (tools
    # echo their arguments back).
    @part.update!(name: "Part #{CANARY}", mpn: "VICTIM-MPN-1")
    @project = @victim.projects.first
    @project.update!(name: "Project #{CANARY}")
    @zone = @victim.storage_locations.where.not(code: nil).first
    @zone.update!(name: "Zone #{CANARY}")
    @loan = @victim.loans.first
    @loan&.update!(borrower_name: "Borrower #{CANARY}")
    @order = @victim.orders.first

    @attacker = create_user(email: "attacker@example.com")
    @attacker_org = @attacker.organizations.first
    create_part(organization: @attacker_org, name: "Mine")
  end

  test "no MCP tool reads or changes another organization" do
    before = victim_rows
    server = McpServer.new(organization: @attacker_org, base_url: "http://x", user: @attacker, client_name: "sweep", write: true)
    tools = call(server, "tools/list")[:result][:tools]
    assert_operator tools.size, :>, 10

    leaks = []
    tools.each do |tool|
      properties = tool[:inputSchema][:properties] || {}
      [ @part.ipn, @part.mpn, @project.reference, @zone.code ].compact.each do |reference|
        arguments = properties.to_h { |key, schema| [ key.to_s, argument_for(key.to_s, schema, reference) ] }
        [ @part.id, @project.id, @zone.id ].each do |id|
          response = call(server, "tools/call", "name" => tool[:name], "arguments" => arguments.merge("id" => id))
          leaks << [ tool[:name], arguments ] if response.to_json.include?(CANARY)
        end
      end
    end

    assert_empty leaks, "MCP tools returned another organization's data: #{leaks.first(3).inspect}"
    assert_equal before, victim_rows, "an MCP tool changed another organization's rows"
  end

  test "the sweep would see a leak: the victim's own owner gets the canary" do
    server = McpServer.new(organization: @victim, base_url: "http://x", user: @owner, client_name: "sweep", write: true)
    response = call(server, "tools/call", "name" => "get_part", "arguments" => { "id" => @part.id })
    assert_includes response.to_json, CANARY
  end

  private

  def call(server, method, params = nil)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params }.compact)
  end

  # The victim's id for *_id arguments, its reference for strings and lines.
  def argument_for(key, schema, reference)
    kind = key.sub(/_id\z/, "").sub(/\A(from|to)_/, "")
    ids = { "part" => @part.id, "project" => @project.id, "storage_location" => @zone.id, "location" => @zone.id,
            "order" => @order&.id, "category" => @part.category_id, "loan" => @loan&.id }
    if key.end_with?("_id") then ids[kind] || @part.id
    elsif schema[:type] == "array" then [ { "reference" => reference, "quantity" => 1, "part" => reference } ]
    elsif %w[integer number].include?(schema[:type]) then 1
    elsif schema[:type] == "boolean" then false
    else reference.to_s
    end
  end

  def victim_rows
    VICTIM_TABLES.transform_values do |sql|
      ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql([ sql, { org: @victim.id } ]))
    end
  end
end

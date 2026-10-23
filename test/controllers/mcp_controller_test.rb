require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @part = create_part(organization: @org, name: "Mine 10k", mpn: "MINE-10K")
    @other_org = create_organization
    OrganizationMembership.create!(organization: @other_org, user: @user, role: "viewer")
    create_part(organization: @other_org, name: "Theirs 10k", mpn: "THEIRS-10K")
    @token = connect_mcp_client(user: @user, organization: @org)[:access_token]
  end

  test "tools only see the organization the token was granted for" do
    result = rpc("tools/call", { name: "search_parts", arguments: { query: "10k" } })

    assert_equal [ "Mine 10k" ], result.dig("structuredContent", "parts").map { |part| part["name"] }
  end

  test "a token for another organization sees that organization only" do
    token = connect_mcp_client(user: @user, organization: @other_org)[:access_token]
    result = rpc("tools/call", { name: "search_parts", arguments: { query: "10k" } }, token: token)

    assert_equal [ "Theirs 10k" ], result.dig("structuredContent", "parts").map { |part| part["name"] }
  end

  test "a viewer can read with the read-only tools" do
    token = connect_mcp_client(user: @user, organization: @other_org)[:access_token]
    assert rpc("tools/call", { name: "inventory_overview", arguments: {} }, token: token)["structuredContent"]
  end

  test "a write grant offers the write tools and records changes in the user's name" do
    location = create_storage_location(organization: @org, code: "DA")
    token = connect_mcp_client(user: @user, organization: @org, write: true)[:access_token]

    assert_includes rpc("tools/list", {}, token: token)["tools"].map { |tool| tool["name"] }, "record_stock_movement"
    assert_not_includes rpc("tools/list")["tools"].map { |tool| tool["name"] }, "record_stock_movement"

    result = rpc("tools/call", { name: "record_stock_movement", arguments: { part: "MINE-10K", direction: "in", quantity: 5, location: "DA" } }, token: token)
    assert_not result["isError"]
    movement = @part.stock_movements.sole
    assert_equal [ @user, location, "Stock added (via Claude)" ], [ movement.user, movement.storage_location, movement.reason ]
  end

  test "changes made by write tools are in the activity log" do
    token = connect_mcp_client(user: @user, organization: @org, write: true)[:access_token]

    result = rpc("tools/call", { name: "update_part", arguments: { part: "MINE-10K", name: "Mine 10k 1%" } }, token: token)
    assert_not result["isError"]
    event = @org.activity_events.newest_first.first
    assert_equal [ "update", @part.id, @user.id, [ "Mine 10k", "Mine 10k 1%" ] ],
      [ event.action, event.subject_id, event.user_id, event.details["name"] ]
  end

  test "write tools go away when the user becomes a viewer, and come back with the role" do
    token = connect_mcp_client(user: @user, organization: @other_org, write: true)[:access_token]
    assert_equal "mcp:read mcp:write", OauthAuthorization.authenticate(token).scope
    assert_not_includes rpc("tools/list", {}, token: token)["tools"].map { |tool| tool["name"] }, "create_part"

    result = rpc("tools/call", { name: "create_part", arguments: { name: "Sneaky" } }, token: token)
    assert result["isError"]
    assert_not @other_org.parts.exists?(name: "Sneaky")

    @user.organization_memberships.find_by(organization: @other_org).update!(role: "member")
    assert_includes rpc("tools/list", {}, token: token)["tools"].map { |tool| tool["name"] }, "create_part"
  end

  test "notifications are accepted without a body" do
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: headers_for(@token)
    assert_response :accepted
    assert_empty response.body
  end

  test "malformed JSON and batches are refused" do
    post "/mcp", params: "{oops", headers: headers_for(@token)
    assert_response :bad_request
    assert_equal McpServer::PARSE_ERROR, response.parsed_body.dig("error", "code")

    post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "ping" } ].to_json, headers: headers_for(@token)
    assert_response :bad_request
    assert_equal McpServer::INVALID_REQUEST, response.parsed_body.dig("error", "code")
  end

  test "a revoked or disconnected grant stops working" do
    @user.oauth_authorizations.destroy_all

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json, headers: headers_for(@token)
    assert_response :unauthorized
  end

  private

  def rpc(method, params = {}, token: @token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers_for(token)
    assert_response :success
    response.parsed_body["result"]
  end

  def headers_for(token)
    { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Authorization" => "Bearer #{token}" }
  end
end

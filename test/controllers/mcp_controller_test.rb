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

  test "a viewer can read: every tool is read-only" do
    token = connect_mcp_client(user: @user, organization: @other_org)[:access_token]
    assert rpc("tools/call", { name: "inventory_overview", arguments: {} }, token: token)["structuredContent"]
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

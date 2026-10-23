require "test_helper"

# The OAuth flow an MCP client (claude.ai, Claude Code) runs against the app:
# discovery, dynamic registration, consent, token exchange, refresh, revocation.
class McpOauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  test "an unauthenticated MCP call points at the protected resource metadata" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json, headers: json_headers

    assert_response :unauthorized
    assert_match %r{resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp"}, response.headers["WWW-Authenticate"]
    assert_no_match(/invalid_token/, response.headers["WWW-Authenticate"])

    post "/mcp", params: "{}", headers: json_headers.merge("Authorization" => "Bearer nope")
    assert_response :unauthorized
    assert_match(/error="invalid_token"/, response.headers["WWW-Authenticate"])
  end

  test "serves the discovery documents" do
    get "/.well-known/oauth-protected-resource/mcp"
    assert_response :success
    assert_equal "http://www.example.com/mcp", response.parsed_body["resource"]
    assert_equal [ "http://www.example.com" ], response.parsed_body["authorization_servers"]

    get "/.well-known/oauth-protected-resource"
    assert_response :success

    get "/.well-known/oauth-authorization-server"
    metadata = response.parsed_body
    assert_equal "http://www.example.com", metadata["issuer"]
    assert_equal "http://www.example.com/oauth/register", metadata["registration_endpoint"]
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_equal [ "none" ], metadata["token_endpoint_auth_methods_supported"]
  end

  test "the whole flow, from registration to an MCP call" do
    client_id = register

    sign_in @user
    verifier, challenge = pkce_pair
    get "/oauth/authorize", params: authorize_params(client_id, challenge)
    assert_response :success
    props = inertia_props
    assert_equal "Claude", props["client_name"]
    assert_equal "claude.ai", props["redirect_host"]
    assert_equal false, props["loopback"]
    assert_equal [ @org.id ], props["organizations"].map { |org| org["id"] }

    post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "allow", organization_id: @org.id)
    location = URI.parse(response.location)
    assert_equal "claude.ai", location.host
    query = Rack::Utils.parse_query(location.query)
    assert_equal "xyz", query["state"]
    assert_equal "http://www.example.com", query["iss"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client_id, code: query["code"],
      redirect_uri: "https://claude.ai/api/mcp/auth_callback", code_verifier: verifier
    }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    tokens = response.parsed_body
    assert_equal "Bearer", tokens["token_type"]
    assert_equal "mcp:read", tokens["scope"], "read-only unless the user allows changes"

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: json_headers.merge("Authorization" => "Bearer #{tokens['access_token']}")
    assert_response :success
    assert_includes response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }, "check_bom"

    post "/oauth/token", params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    assert_response :success
    assert_not_equal tokens["access_token"], response.parsed_body["access_token"]

    post "/oauth/token", params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]

    post "/oauth/revoke", params: { token: response.parsed_body["refresh_token"] }
    assert_response :success
  end

  test "registration refuses unsafe redirect URIs" do
    post "/oauth/register", params: { client_name: "Evil", redirect_uris: [ "http://evil.example/cb" ] }.to_json, headers: json_headers

    assert_response :bad_request
    assert_equal "invalid_redirect_uri", response.parsed_body["error"]
  end

  test "Claude Code's loopback redirect works on any port and is flagged on the consent page" do
    post "/oauth/register", params: { client_name: "Claude Code", redirect_uris: [ "http://localhost/callback" ] }.to_json, headers: json_headers
    client_id = response.parsed_body["client_id"]

    sign_in @user
    _verifier, challenge = pkce_pair
    get "/oauth/authorize", params: authorize_params(client_id, challenge, redirect_uri: "http://localhost:43123/callback")

    assert_response :success
    assert_equal true, inertia_props["loopback"]
  end

  test "the consent page asks a signed-out visitor to log in first" do
    client_id = register
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params(client_id, challenge)
    assert_redirected_to new_user_session_path
  end

  test "an unknown client or unregistered redirect URI is never redirected to" do
    client_id = register
    sign_in @user
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params("unknown", challenge)
    assert_response :bad_request
    assert inertia_props["error"].present?

    get "/oauth/authorize", params: authorize_params(client_id, challenge, redirect_uri: "https://evil.example/cb")
    assert_response :bad_request
    assert inertia_props["error"].present?
  end

  test "requests without PKCE go back to the client with an error" do
    client_id = register
    sign_in @user

    get "/oauth/authorize", params: authorize_params(client_id, "").merge(code_challenge_method: "plain")
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "invalid_request", query["error"]
    assert_equal "xyz", query["state"]
  end

  test "allowing changes grants the write scope, but never in an organization the user only views" do
    client_id = register
    viewed = create_organization
    OrganizationMembership.create!(organization: viewed, user: @user, role: "viewer")
    sign_in @user
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params(client_id, challenge).merge(scope: "mcp:read mcp:write")
    props = inertia_props
    assert props["write_requested"]
    assert_equal({ @org.id => true, viewed.id => false }, props["organizations"].to_h { |org| [ org["id"], org["can_write"] ] })

    post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "allow", organization_id: @org.id, write: "true")
    assert_equal "mcp:read mcp:write", OauthAuthorization.order(:id).last.scope

    post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "allow", organization_id: viewed.id, write: "true")
    assert_equal "mcp:read", OauthAuthorization.order(:id).last.scope

    get "/.well-known/oauth-authorization-server"
    assert_equal %w[mcp:read mcp:write], response.parsed_body["scopes_supported"]
  end

  test "denying sends access_denied back, and no access is granted" do
    client_id = register
    sign_in @user
    _verifier, challenge = pkce_pair

    assert_no_difference "OauthAuthorization.count" do
      post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "deny", organization_id: @org.id)
    end
    assert_equal "access_denied", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
  end

  test "an organization the user doesn't belong to can't be granted" do
    client_id = register
    sign_in @user
    _verifier, challenge = pkce_pair

    assert_no_difference "OauthAuthorization.count" do
      post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "allow", organization_id: create_organization.id)
    end
    assert_redirected_to %r{/oauth/authorize}
  end

  test "an Inertia consent gets a location visit to the client" do
    client_id = register
    sign_in @user
    _verifier, challenge = pkce_pair

    post "/oauth/authorize", params: authorize_params(client_id, challenge).merge(decision: "allow", organization_id: @org.id),
      headers: { "X-Inertia" => "true" }
    assert_response :conflict
    assert response.headers["X-Inertia-Location"].start_with?("https://claude.ai/api/mcp/auth_callback?code=")
  end

  test "the token endpoint rejects unknown clients and grant types" do
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: "nope", code: "x" }
    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]

    post "/oauth/token", params: { grant_type: "client_credentials", client_id: register }
    assert_response :bad_request
    assert_equal "unsupported_grant_type", response.parsed_body["error"]
  end

  test "the MCP endpoint only answers POST" do
    get "/mcp"
    assert_response :method_not_allowed
    delete "/mcp"
    assert_response :method_not_allowed
  end

  private

  def register
    post "/oauth/register", params: {
      client_name: "Claude", redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ],
      token_endpoint_auth_method: "none", grant_types: %w[authorization_code refresh_token]
    }.to_json, headers: json_headers
    assert_response :created
    response.parsed_body["client_id"]
  end

  def authorize_params(client_id, challenge, redirect_uri: "https://claude.ai/api/mcp/auth_callback")
    {
      response_type: "code", client_id: client_id, redirect_uri: redirect_uri,
      code_challenge: challenge, code_challenge_method: "S256", state: "xyz", scope: "mcp:read"
    }
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

require "application_system_test_case"

class McpConnectTest < ApplicationSystemTestCase
  test "a user signs in from the consent page, allows access, and can disconnect from the profile" do
    user = create_user
    org = user.organizations.first
    # Loopback redirect, as Claude Code registers it: any port matches, so the
    # code comes back to the test server's health check.
    client = create_oauth_client(name: "Claude Code", redirect_uris: [ "http://127.0.0.1/up" ])
    verifier, challenge = pkce_pair

    visit oauth_authorize_path(response_type: "code", client_id: client.uid, redirect_uri: "#{Capybara.current_session.server.base_url}/up",
                               code_challenge: challenge, code_challenge_method: "S256", state: "s1")
    fill_in "Email address", with: user.email
    fill_in "Password", with: "password123"
    click_on "Log in"

    assert_text "Allow Claude Code?", wait: 20
    assert_text "An application on your computer"
    click_on "Allow access"

    assert_current_path(/code=/, url: true, wait: 10)
    query = Rack::Utils.parse_query(URI.parse(current_url).query)
    assert_equal "s1", query["state"]
    tokens = OauthAuthorization.exchange_code!(client: client, code: query["code"], redirect_uri: "#{Capybara.current_session.server.base_url}/up", code_verifier: verifier)
    assert_equal org, OauthAuthorization.authenticate(tokens[:access_token]).organization

    visit profile_path
    assert_text "Claude & AI assistants", wait: 20
    assert_selector "input[aria-label='MCP server URL'][value='#{Capybara.current_session.server.base_url}/mcp']"
    assert_text "Claude Code"
    click_on "Disconnect"
    assert_text "Claude Code disconnected.", wait: 10
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
  end
end

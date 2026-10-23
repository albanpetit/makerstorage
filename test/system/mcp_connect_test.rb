require "application_system_test_case"

class McpConnectTest < ApplicationSystemTestCase
  test "a user signs in from the consent page, allows changes, and can make it read-only or disconnect from the profile" do
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
    find("button#allow_changes").click
    assert_selector "button#allow_changes[aria-checked='true']"
    click_on "Allow access"

    assert_current_path(/code=/, url: true, wait: 10)
    query = Rack::Utils.parse_query(URI.parse(current_url).query)
    assert_equal "s1", query["state"]
    tokens = OauthAuthorization.exchange_code!(client: client, code: query["code"], redirect_uri: "#{Capybara.current_session.server.base_url}/up", code_verifier: verifier)
    authorization = OauthAuthorization.authenticate(tokens[:access_token])
    assert_equal org, authorization.organization
    assert authorization.can_write?

    visit profile_path
    assert_text "Claude & AI assistants", wait: 20
    assert_selector "input[aria-label='MCP server URL'][value='#{Capybara.current_session.server.base_url}/mcp']"
    assert_text "Claude Code"
    find("button#connected_app_write_#{authorization.id}[aria-checked='true']").click
    assert_text "Claude Code is now read-only.", wait: 10
    assert_not authorization.reload.write_scope?
    click_on "Disconnect"
    assert_text "Claude Code disconnected.", wait: 10
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
  end
end

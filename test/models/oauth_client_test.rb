require "test_helper"

class OauthClientTest < ActiveSupport::TestCase
  test "generates a client id and keeps the redirect URIs" do
    client = create_oauth_client(redirect_uris: [ "https://claude.ai/api/mcp/auth_callback", "http://localhost/callback" ])

    assert client.uid.present?
    assert_equal [ "https://claude.ai/api/mcp/auth_callback", "http://localhost/callback" ], client.reload.redirect_uris
  end

  test "only accepts https redirect URIs, or http on a loopback host" do
    assert OauthClient.new(name: "x", redirect_uris: [ "http://127.0.0.1:3118/callback" ]).valid?
    assert OauthClient.new(name: "x", redirect_uris: [ "http://[::1]/callback" ]).valid?

    [
      [], [ "http://evil.example/callback" ], [ "javascript:alert(1)" ], [ "https://claude.ai/cb#fragment" ],
      [ "https://user:pass@claude.ai/cb" ], [ "not a uri" ], [ { "uri" => "https://claude.ai" } ],
      Array.new(OauthClient::MAX_REDIRECT_URIS + 1) { |i| "https://claude.ai/#{i}" }
    ].each do |uris|
      assert_not OauthClient.new(name: "x", redirect_uris: uris).valid?, "accepted #{uris.inspect}"
    end
  end

  test "matches redirect URIs exactly, except loopback ports" do
    client = create_oauth_client(redirect_uris: [ "https://claude.ai/api/mcp/auth_callback", "http://localhost/callback" ])

    assert client.redirect_uri_allowed?("https://claude.ai/api/mcp/auth_callback")
    assert client.redirect_uri_allowed?("http://localhost:51234/callback")
    assert_not client.redirect_uri_allowed?("https://claude.ai/api/mcp/auth_callback/other")
    assert_not client.redirect_uri_allowed?("https://claude.ai:8443/api/mcp/auth_callback")
    assert_not client.redirect_uri_allowed?("http://localhost:51234/elsewhere")
    assert_not client.redirect_uri_allowed?("http://127.0.0.1:51234/callback")
    assert_not client.redirect_uri_allowed?("")
  end

  test "deleting a client removes the access it was granted" do
    user = create_user
    client = create_oauth_client
    connect_mcp_client(user: user, organization: user.organizations.first, client: client)

    assert_difference "OauthAuthorization.count", -1 do
      client.destroy
    end
  end
end

require "test_helper"

class OauthAuthorizationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @client = create_oauth_client
    @redirect_uri = @client.redirect_uris.first
    @verifier, @challenge = pkce_pair
  end

  test "a code is exchanged once for tokens that authenticate the user on the organization" do
    code = grant
    tokens = exchange(code)

    assert tokens[:access_token].start_with?(OauthAuthorization::ACCESS_TOKEN_PREFIX)
    assert tokens[:refresh_token].start_with?(OauthAuthorization::REFRESH_TOKEN_PREFIX)
    assert_equal OauthAuthorization::ACCESS_TOKEN_TTL.to_i, tokens[:expires_in]

    authorization = OauthAuthorization.authenticate(tokens[:access_token])
    assert_equal @user, authorization.user
    assert_equal @org, authorization.organization
    assert authorization.last_used_at.present?
  end

  test "stores only digests of codes and tokens" do
    code = grant
    tokens = exchange(code)
    authorization = OauthAuthorization.last

    stored = authorization.attributes.values.map(&:to_s)
    [ code, tokens[:access_token], tokens[:refresh_token] ].each { |secret| assert_not_includes stored, secret }
  end

  test "rejects a wrong PKCE verifier, redirect URI, client or an expired code" do
    code = grant
    assert_raises(OauthAuthorization::InvalidGrant) { exchange(code, code_verifier: pkce_pair.first) }
    assert_raises(OauthAuthorization::InvalidGrant) { exchange(code, redirect_uri: "https://claude.ai/other") }
    assert_raises(OauthAuthorization::InvalidGrant) { exchange(code, client: create_oauth_client) }
    assert_raises(OauthAuthorization::InvalidGrant) { exchange("unknown") }

    expired = grant
    travel OauthAuthorization::CODE_TTL + 1.second do
      assert_raises(OauthAuthorization::InvalidGrant) { exchange(expired) }
    end
  end

  test "replaying a used code revokes what it granted" do
    code = grant
    tokens = exchange(code)

    assert_raises(OauthAuthorization::InvalidGrant) { exchange(code) }
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
  end

  test "refreshing rotates both tokens" do
    tokens = exchange(grant)
    refreshed = OauthAuthorization.refresh!(client: @client, refresh_token: tokens[:refresh_token])

    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
    assert OauthAuthorization.authenticate(refreshed[:access_token])
    assert_raises(OauthAuthorization::InvalidGrant) { OauthAuthorization.refresh!(client: @client, refresh_token: tokens[:refresh_token]) }
    assert_raises(OauthAuthorization::InvalidGrant) { OauthAuthorization.refresh!(client: create_oauth_client, refresh_token: refreshed[:refresh_token]) }
  end

  test "access tokens expire" do
    tokens = exchange(grant)

    travel OauthAuthorization::ACCESS_TOKEN_TTL + 1.second do
      assert_nil OauthAuthorization.authenticate(tokens[:access_token])
      assert OauthAuthorization.refresh!(client: @client, refresh_token: tokens[:refresh_token])
    end
  end

  test "losing access to the organization or being locked out stops the tokens" do
    other = create_organization
    membership = OrganizationMembership.create!(organization: other, user: @user, role: "viewer")
    tokens = connect_mcp_client(user: @user, organization: other, client: @client)
    assert OauthAuthorization.authenticate(tokens[:access_token])

    membership.update!(active: false)
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
    assert_raises(OauthAuthorization::InvalidGrant) { OauthAuthorization.refresh!(client: @client, refresh_token: tokens[:refresh_token]) }

    tokens = exchange(grant)
    @user.lock_access!(send_instructions: false)
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
  end

  test "writes only with the write scope and a writing role, and keeps the scope across refreshes" do
    read_only = OauthAuthorization.find_by(code_digest: OauthAuthorization.digest(grant))
    assert_equal "mcp:read", read_only.scope
    assert_not read_only.can_write?

    @verifier, @challenge = pkce_pair
    code = OauthAuthorization.grant!(client: @client, user: @user, organization: @org, redirect_uri: @redirect_uri,
                                     code_challenge: @challenge, write: true)
    tokens = exchange(code)
    assert_equal "mcp:read mcp:write", tokens[:scope]
    authorization = OauthAuthorization.authenticate(tokens[:access_token])
    assert authorization.can_write?

    assert_equal "mcp:read mcp:write", OauthAuthorization.refresh!(client: @client, refresh_token: tokens[:refresh_token])[:scope]

    @user.organization_memberships.find_by(organization: @org).update_column(:role, "viewer")
    assert authorization.reload.write_scope?
    assert_not authorization.can_write?, "a viewer's grant can't write"

    authorization.allow_write!(false)
    assert_equal "mcp:read", authorization.reload.scope
  end

  test "can't be granted on an organization the user doesn't belong to" do
    assert_raises(ActiveRecord::RecordInvalid) do
      OauthAuthorization.grant!(client: @client, user: @user, organization: create_organization,
                                redirect_uri: @redirect_uri, code_challenge: @challenge)
    end
  end

  test "granting sweeps codes nobody exchanged" do
    grant
    travel OauthAuthorization::CODE_TTL + 1.second do
      assert_no_difference "OauthAuthorization.count" do
        grant
      end
    end
  end

  test "goes away with its organization, and with its user" do
    exchange(grant)
    assert_difference("OauthAuthorization.count", -1) { @org.destroy }
    assert_equal :delete_all, User.reflect_on_association(:oauth_authorizations).options[:dependent]
  end

  private

  def grant
    OauthAuthorization.grant!(client: @client, user: @user, organization: @org, redirect_uri: @redirect_uri, code_challenge: @challenge)
  end

  def exchange(code, client: @client, redirect_uri: @redirect_uri, code_verifier: @verifier)
    OauthAuthorization.exchange_code!(client: client, code: code, redirect_uri: redirect_uri, code_verifier: code_verifier)
  end
end

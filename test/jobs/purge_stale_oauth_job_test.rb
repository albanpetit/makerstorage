require "test_helper"

class PurgeStaleOauthJobTest < ActiveJob::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  test "deletes unused codes and grants whose refresh token expired, keeps live grants" do
    live_client = create_oauth_client
    connect_mcp_client(user: @user, organization: @org, client: live_client)
    live = OauthAuthorization.find_by!(oauth_client: live_client)

    expired_client = create_oauth_client
    connect_mcp_client(user: @user, organization: @org, client: expired_client)
    expired = OauthAuthorization.find_by!(oauth_client: expired_client)
    expired.update_columns(refresh_token_expires_at: 1.day.ago)

    _, challenge = pkce_pair
    OauthAuthorization.grant!(client: live_client, user: @user, organization: @org,
                              redirect_uri: live_client.redirect_uris.first, code_challenge: challenge)
    abandoned = OauthAuthorization.where(access_token_digest: nil).sole
    abandoned.update_columns(code_expires_at: 1.minute.ago)

    PurgeStaleOauthJob.perform_now

    assert OauthAuthorization.exists?(live.id)
    assert_not OauthAuthorization.exists?(expired.id)
    assert_not OauthAuthorization.exists?(abandoned.id)
  end

  test "deletes old clients that hold no authorization" do
    unused = create_oauth_client
    unused.update_columns(created_at: 31.days.ago)
    recent = create_oauth_client
    in_use = create_oauth_client
    in_use.update_columns(created_at: 1.year.ago)
    connect_mcp_client(user: @user, organization: @org, client: in_use)

    PurgeStaleOauthJob.perform_now

    assert_not OauthClient.exists?(unused.id)
    assert OauthClient.exists?(recent.id)
    assert OauthClient.exists?(in_use.id)
  end

  test "is scheduled in production" do
    jobs = YAML.load_file(Rails.root.join("config/recurring.yml"))["production"]
    assert jobs.values.any? { |job| job["class"] == "PurgeStaleOauthJob" }
  end
end

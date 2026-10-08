require "test_helper"

class Oauth::DigikeyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(digikey_client_id: "cid", digikey_client_secret: "csecret")
  end

  test "authorize redirects to DigiKey with a state stored in the session" do
    sign_in @user
    get oauth_digikey_authorize_path

    assert_response :redirect
    assert_match %r{api\.digikey\.com/v1/oauth2/authorize}, response.location
    assert_match(/state=/, response.location)
    assert response.location.include?("client_id=cid")
  end

  test "authorize without credentials sends the user back to settings" do
    @org.update!(digikey_client_id: nil, digikey_client_secret: nil)
    sign_in @user
    get oauth_digikey_authorize_path
    assert_redirected_to settings_path
    assert_match(/client id and secret/i, flash[:alert])
  end

  test "callback with a matching state stores the tokens" do
    sign_in @user
    get oauth_digikey_authorize_path
    state = session[:digikey_oauth_state]
    assert state.present?

    tokens = { "access_token" => "acc", "refresh_token" => "ref", "expires_in" => 1800 }
    stub_singleton(SupplierCatalog::Digikey, :exchange_code, ->(**_kw) { tokens }) do
      get oauth_digikey_callback_path(code: "the-code", state: state)
    end

    assert_redirected_to settings_path
    @org.reload
    assert @org.digikey_account_connected?
    assert_equal "acc", @org.digikey_access_token
    assert @org.digikey_token_expires_at > Time.current
  end

  test "callback rejects a mismatched state" do
    sign_in @user
    get oauth_digikey_callback_path(code: "x", state: "not-the-state")
    assert_redirected_to settings_path
    assert_match(/could not be verified/i, flash[:alert])
    assert_not @org.reload.digikey_account_connected?
  end

  test "callback handles a denied authorization" do
    sign_in @user
    get oauth_digikey_authorize_path
    state = session[:digikey_oauth_state]
    get oauth_digikey_callback_path(error: "access_denied", state: state)
    assert_redirected_to settings_path
    assert_match(/cancelled/i, flash[:alert])
  end

  test "disconnect clears the stored tokens" do
    @org.update!(digikey_access_token: "a", digikey_refresh_token: "r", digikey_token_expires_at: 1.hour.from_now)
    sign_in @user
    delete oauth_digikey_path
    assert_redirected_to settings_path
    assert_not @org.reload.digikey_account_connected?
  end

  test "viewers cannot start the connection" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"
    get oauth_digikey_authorize_path
    assert_redirected_to root_path
  end

  test "callback refuses tokens when the organization changed mid-handshake" do
    other = Organization.create!(name: "Other lab")
    OrganizationMembership.create!(organization: other, user: @user, role: "owner")
    other.update!(digikey_client_id: "cid2", digikey_client_secret: "csecret2")

    sign_in @user
    get oauth_digikey_authorize_path
    state = session[:digikey_oauth_state]
    post switch_organization_path(other)

    tokens = { "access_token" => "acc", "refresh_token" => "ref", "expires_in" => 1800 }
    stub_singleton(SupplierCatalog::Digikey, :exchange_code, ->(**_kw) { tokens }) do
      get oauth_digikey_callback_path(code: "the-code", state: state)
    end

    assert_redirected_to settings_path
    assert_match(/switched organization/i, flash[:alert])
    assert_nil other.reload.digikey_refresh_token
    assert_nil @org.reload.digikey_refresh_token
  end
end

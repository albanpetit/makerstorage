require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get settings_path
    assert_redirected_to new_user_session_path
  end

  test "show is forbidden for a non-admin member" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    get settings_path

    assert_redirected_to root_path
  end

  test "show renders organization settings for an owner" do
    user = create_user
    org = user.organizations.first
    org.update!(name: "Acme Fablab", currency: "USD", ipn_prefix: "AC", ipn_next_sequence: 41)

    sign_in user
    get settings_path
    assert_response :success

    organization = inertia_props["organization"]
    assert_equal "Acme Fablab", organization["name"]
    assert_equal "USD", organization["currency"]
    assert_equal "AC-RES-00041", organization["ipn_preview"]["next"]
    assert_includes inertia_props["currencies"], "USD"
  end

  test "update is forbidden for a non-admin member" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    patch settings_path, params: { organization: { name: "Hacked" } }

    assert_redirected_to root_path
    assert_not_equal "Hacked", org.reload.name
  end

  test "update updates general profile and regional fields" do
    user = create_user
    org = user.organizations.first

    sign_in user
    patch settings_path, params: { organization: {
      name: "New Name", email: "org@example.com", currency: "GBP", timezone: "Europe/London"
    } }

    assert_redirected_to settings_path
    org.reload
    assert_equal "New Name", org.name
    assert_equal "org@example.com", org.email
    assert_equal "GBP", org.currency
    assert_equal "Europe/London", org.timezone
  end

  test "update updates IPN numbering fields" do
    user = create_user
    org = user.organizations.first

    sign_in user
    patch settings_path, params: { organization: {
      ipn_generation_mode: "random", ipn_charset: "alphanumeric",
      ipn_prefix: "ZZ", ipn_separator: "_", ipn_digits: 6, ipn_use_category_code: false, ipn_next_sequence: 99
    } }

    assert_redirected_to settings_path
    org.reload
    assert_equal "random", org.ipn_generation_mode
    assert_equal "alphanumeric", org.ipn_charset
    assert_equal "ZZ", org.ipn_prefix
    assert_equal "_", org.ipn_separator
    assert_equal 6, org.ipn_digits
    assert_equal false, org.ipn_use_category_code
    assert_equal 99, org.ipn_next_sequence
  end

  test "reassign_ipns renumbers existing parts with the current format" do
    user = create_user
    org = user.organizations.first
    org.update!(ipn_generation_mode: "incremental", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 40)
    category = create_category(organization: org)
    part = create_part(organization: org, category: category)

    sign_in user
    post reassign_ipns_settings_path

    assert_redirected_to settings_path
    assert_equal "MS-00001", part.reload.ipn
  end

  test "reassign_ipns is forbidden for a non-admin member" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    post reassign_ipns_settings_path

    assert_redirected_to root_path
  end

  test "reassign_ipns refuses in manual mode" do
    user = create_user
    org = user.organizations.first
    org.update!(ipn_generation_mode: "manual")
    part = create_part(organization: org, category: create_category(organization: org), ipn: "KEEP")

    sign_in user
    post reassign_ipns_settings_path

    assert_redirected_to settings_path
    assert_equal "KEEP", part.reload.ipn
  end

  test "update updates inventory defaults" do
    user = create_user
    org = user.organizations.first

    sign_in user
    patch settings_path, params: { organization: {
      default_low_stock_threshold: 75, allow_negative_stock: true
    } }

    assert_redirected_to settings_path
    org.reload
    assert_equal 75, org.default_low_stock_threshold
    assert_equal true, org.allow_negative_stock
  end

  test "update attaches an uploaded logo" do
    user = create_user
    org = user.organizations.first

    sign_in user
    patch settings_path, params: { organization: { logo: fixture_file_upload("logo.png", "image/png") } }

    assert_redirected_to settings_path
    assert org.reload.logo.attached?
  end

  test "update purges the logo when remove_logo is set" do
    user = create_user
    org = user.organizations.first
    org.logo.attach(io: File.open(Rails.root.join("test/fixtures/files/logo.png")), filename: "logo.png", content_type: "image/png")
    assert org.logo.attached?

    sign_in user
    patch settings_path, params: { organization: { remove_logo: "1" } }

    assert_redirected_to settings_path
    assert_not org.reload.logo.attached?
  end

  test "update keeps the logo when the rest of the form is rejected" do
    user = create_user
    org = user.organizations.first
    org.logo.attach(io: File.open(Rails.root.join("test/fixtures/files/logo.png")), filename: "logo.png", content_type: "image/png")

    sign_in user
    patch settings_path, params: { organization: { remove_logo: "1", email: "not-an-email" } }

    assert org.reload.logo.attached?
  end

  test "show exposes the logo url when a logo is attached" do
    user = create_user
    org = user.organizations.first
    org.logo.attach(io: File.open(Rails.root.join("test/fixtures/files/logo.png")), filename: "logo.png", content_type: "image/png")

    sign_in user
    get settings_path

    assert_not_nil inertia_props["organization"]["logo_url"]
  end

  test "update redirects with an alert and keeps prior values on validation failure" do
    user = create_user
    org = user.organizations.first

    sign_in user
    patch settings_path, params: { organization: { currency: "JPY" } }

    assert_redirected_to settings_path
    follow_redirect!
    assert_match(/Failed to update settings/, flash[:alert])
    assert_equal "EUR", org.reload.currency
    # Error keys are namespaced to match the nested `organization` form so the
    # frontend can render them inline (Rails' flat keys would never match).
    assert inertia_props.dig("errors", "organization.currency").present?
  end

  test "update stores a Mouser API key without echoing the secret back" do
    user = create_user
    org = user.organizations.first
    sign_in user

    patch settings_path, params: { organization: { mouser_api_key: "  secret-key  " } }
    assert_equal "secret-key", org.reload.mouser_api_key

    get settings_path
    organization = inertia_props["organization"]
    assert_equal true, organization["mouser_api_key_present"]
    refute organization.key?("mouser_api_key")
  end

  test "update leaves an existing Mouser key untouched on a blank submit" do
    user = create_user
    org = user.organizations.first
    org.update!(mouser_api_key: "existing-key")
    sign_in user

    patch settings_path, params: { organization: { name: "Renamed", mouser_api_key: "" } }
    assert_equal "existing-key", org.reload.mouser_api_key
    assert_equal "Renamed", org.name
  end

  test "update clears the Mouser key when the remove flag is set" do
    user = create_user
    org = user.organizations.first
    org.update!(mouser_api_key: "existing-key")
    sign_in user

    patch settings_path, params: { organization: { remove_mouser_api_key: "true" } }
    assert_nil org.reload.mouser_api_key
  end

  test "update stores DigiKey credentials without echoing the secret back" do
    user = create_user
    org = user.organizations.first
    sign_in user

    patch settings_path, params: { organization: { digikey_client_id: "  cid  ", digikey_client_secret: "  csecret  " } }
    org.reload
    assert_equal "cid", org.digikey_client_id
    assert_equal "csecret", org.digikey_client_secret

    get settings_path
    organization = inertia_props["organization"]
    assert_equal true, organization["digikey_configured"]
    refute organization.key?("digikey_client_id")
    refute organization.key?("digikey_client_secret")
  end

  test "update leaves existing DigiKey credentials untouched on a blank submit" do
    user = create_user
    org = user.organizations.first
    org.update!(digikey_client_id: "existing-id", digikey_client_secret: "existing-secret")
    sign_in user

    patch settings_path, params: { organization: { name: "Renamed", digikey_client_id: "", digikey_client_secret: "" } }
    org.reload
    assert_equal "existing-id", org.digikey_client_id
    assert_equal "existing-secret", org.digikey_client_secret
    assert_equal "Renamed", org.name
  end

  test "update clears DigiKey credentials when the remove flag is set" do
    user = create_user
    org = user.organizations.first
    org.update!(digikey_client_id: "existing-id", digikey_client_secret: "existing-secret")
    sign_in user

    patch settings_path, params: { organization: { remove_digikey: "true" } }
    org.reload
    assert_nil org.digikey_client_id
    assert_nil org.digikey_client_secret
  end

  test "removing DigiKey credentials also disconnects the linked account" do
    user = create_user
    org = user.organizations.first
    org.update!(digikey_client_id: "existing-id", digikey_client_secret: "existing-secret",
                digikey_access_token: "at", digikey_refresh_token: "rt", digikey_token_expires_at: 1.hour.from_now)
    sign_in user

    patch settings_path, params: { organization: { remove_digikey: "true" } }
    org.reload
    assert_not org.digikey_account_connected?
    assert_nil org.digikey_access_token
    assert_nil org.digikey_token_expires_at
  end

  test "adding a Mouser key recreates its supplier and announces it" do
    user = create_user
    org = user.organizations.first
    org.suppliers.where(catalog_provider: "mouser").destroy_all
    sign_in user

    assert_difference -> { org.suppliers.where(catalog_provider: "mouser").count } => 1 do
      patch settings_path, params: { organization: { mouser_api_key: "secret-key" } }
    end

    assert_match "Mouser Electronics", flash[:notice]
  end

  test "adding a Mouser key does not duplicate an existing supplier" do
    user = create_user
    org = user.organizations.first # already seeded with a Mouser supplier
    sign_in user

    assert_no_difference -> { org.suppliers.where(catalog_provider: "mouser").count } do
      patch settings_path, params: { organization: { mouser_api_key: "secret-key" } }
    end

    refute_match(/Mouser Electronics/, flash[:notice].to_s)
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

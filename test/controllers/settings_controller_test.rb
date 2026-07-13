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

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get search_path, params: { q: "res" }
    assert_redirected_to new_user_session_path
  end

  test "returns empty groups for a query shorter than the minimum length" do
    user = create_user
    org = user.organizations.first
    create_part(organization: org, name: "Resistor", mpn: "R-1")

    sign_in user
    get search_path, params: { q: "r" }
    assert_response :success

    body = JSON.parse(@response.body)
    assert_empty body["parts"]
    assert_empty body["zones"]
  end

  test "finds parts by reference or name and zones by name or code" do
    user = create_user
    org = user.organizations.first
    create_part(organization: org, name: "Resistor 4.7k", mpn: "R-0603-4K7")
    create_storage_location(organization: org, name: "Resin cabinet", code: "Z-RES")

    sign_in user
    get search_path, params: { q: "res" }
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal [ "R-0603-4K7" ], body["parts"].map { |p| p["reference"] }
    assert_equal [ "Resin cabinet" ], body["zones"].map { |z| z["name"] }
  end

  test "matches a storage zone by its code" do
    user = create_user
    org = user.organizations.first
    create_storage_location(organization: org, name: "Drawer A1", code: "QR-A1-01")

    sign_in user
    get search_path, params: { q: "qr-a1" }
    assert_equal [ "Drawer A1" ], JSON.parse(@response.body)["zones"].map { |z| z["name"] }
  end

  test "does not leak another organization's parts or zones" do
    user = create_user
    other_org = create_organization
    create_part(organization: other_org, name: "Foreign resistor", mpn: "FOREIGN-1")
    create_storage_location(organization: other_org, name: "Foreign zone", code: "FOR-1")

    sign_in user
    get search_path, params: { q: "foreign" }
    assert_response :success

    body = JSON.parse(@response.body)
    assert_empty body["parts"]
    assert_empty body["zones"]
  end
end

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "renders the dashboard for a signed-in user" do
    user = create_user
    sign_in user
    get root_path

    assert_response :success
  end

  test "reflects real stats for the current organization" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)

    low = create_part(organization: org, category: category, min_stock_threshold: 50)
    PartStorage.create!(part: low, storage_location: location, quantity: 5)

    ok = create_part(organization: org, category: category, min_stock_threshold: 10)
    PartStorage.create!(part: ok, storage_location: location, quantity: 100)

    sign_in user
    get root_path
    assert_response :success

    props = inertia_props
    assert_equal 2, props["stats"]["references_count"]
    assert_equal 105, props["stats"]["total_units"]
    assert_equal 1, props["stats"]["alerts_count"]
  end

  test "low_stock_parts lists parts under threshold, most critical first" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org, name: "Shelf A")

    barely_low = create_part(organization: org, category: category, mpn: "RES-BARELY", min_stock_threshold: 100)
    PartStorage.create!(part: barely_low, storage_location: location, quantity: 90)

    critically_low = create_part(organization: org, category: category, mpn: "RES-CRITICAL", min_stock_threshold: 100)
    PartStorage.create!(part: critically_low, storage_location: location, quantity: 1)

    ok = create_part(organization: org, category: category, mpn: "RES-OK", min_stock_threshold: 10)
    PartStorage.create!(part: ok, storage_location: location, quantity: 100)

    sign_in user
    get root_path
    assert_response :success

    low_stock = inertia_props["low_stock_parts"]
    assert_equal [ "RES-CRITICAL", "RES-BARELY" ], low_stock.map { |p| p["reference"] }
    assert_equal "Shelf A", low_stock.first["location_name"]
    assert_equal 1, low_stock.first["quantity"]
    assert_equal 100, low_stock.first["min_stock_threshold"]
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

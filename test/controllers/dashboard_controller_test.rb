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

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

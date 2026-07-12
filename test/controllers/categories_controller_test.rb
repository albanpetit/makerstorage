require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    post categories_path, params: { category: { name: "Resistors" } }
    assert_redirected_to new_user_session_path
  end

  test "create adds a category to the current organization" do
    user = create_user
    org = user.organizations.first

    sign_in user
    assert_difference -> { org.categories.count }, 1 do
      post categories_path, params: { category: { name: "Resistors", color: "#EF4444" } }
    end

    category = org.categories.order(:created_at).last
    assert_equal "Resistors", category.name
    assert_equal "#EF4444", category.color
  end

  test "create supports nesting under a parent of the same organization" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives")

    sign_in user
    post categories_path, params: { category: { name: "Capacitors", parent_id: parent.id } }

    child = org.categories.find_by(name: "Capacitors")
    assert_equal parent.id, child.parent_id
  end

  test "create fails with a blank name and returns errors" do
    user = create_user
    org = user.organizations.first

    sign_in user
    assert_no_difference -> { org.categories.count } do
      post categories_path, params: { category: { name: "" } }
    end
    follow_redirect!
    assert_match(/Failed to create category/, flash[:alert])
  end

  test "create is forbidden for a viewer" do
    owner = create_user
    org = owner.organizations.first
    viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")

    sign_in viewer
    assert_no_difference -> { org.categories.count } do
      post categories_path, params: { category: { name: "Sneaky" } }
    end
  end

  test "create does not attach to another organization even if parent_id points elsewhere" do
    user = create_user
    org = user.organizations.first
    other_org = create_organization
    foreign_parent = create_category(organization: other_org, name: "Foreign")

    sign_in user
    assert_no_difference -> { org.categories.count } do
      post categories_path, params: { category: { name: "Child", parent_id: foreign_parent.id } }
    end
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

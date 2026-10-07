require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    post categories_path, params: { category: { name: "Resistors" } }
    assert_redirected_to new_user_session_path
  end

  test "index serializes categories with parent and part counts" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives", code: "PAS", color: "#3B82F6")
    child = create_category(organization: org, name: "Resistors", parent: parent)
    create_part(organization: org, category: child)

    sign_in user
    get categories_path
    assert_response :success

    parent_json = inertia_props["categories"].find { |c| c["id"] == parent.id }
    child_json = inertia_props["categories"].find { |c| c["id"] == child.id }
    assert_equal "PAS", parent_json["code"]
    assert_equal "#3B82F6", parent_json["color"]
    assert_nil parent_json["parent_id"]
    assert_equal parent.id, child_json["parent_id"]
    assert_equal 1, child_json["parts_count"]
  end

  test "index does not leak another organization's categories" do
    user = create_user
    other_org = create_organization
    create_category(organization: other_org, name: "Someone else's category")

    sign_in user
    get categories_path
    assert_response :success

    names = inertia_props["categories"].map { |c| c["name"] }
    assert_not_includes names, "Someone else's category"
  end

  test "update edits a category" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Old Name")

    sign_in user
    patch category_path(category), params: { category: { name: "Resistors", code: "RES" } }

    assert_redirected_to categories_path
    assert_equal "Resistors", category.reload.name
    assert_equal "RES", category.code
  end

  test "update rejects a parent that is a descendant" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives")
    child = create_category(organization: org, name: "Resistors", parent: parent)

    sign_in user
    patch category_path(parent), params: { category: { parent_id: child.id } }

    assert_nil parent.reload.parent_id
  end

  test "destroy removes a category and cascades to subcategories" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives")
    create_category(organization: org, name: "Resistors", parent: parent)

    sign_in user
    assert_difference -> { Category.count } => -2 do
      delete category_path(parent)
    end

    assert_redirected_to categories_path
  end

  test "destroy without a target is refused while parts reference the category" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    create_part(organization: org, category: category)

    sign_in user
    assert_no_difference "Category.count" do
      delete category_path(category)
    end

    assert_redirected_to categories_path
    follow_redirect!
    assert_match(/move this category's parts/i, flash[:alert])
  end

  test "destroy moves the category's parts to the chosen target then deletes it" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    target = create_category(organization: org, name: "Passives")
    part = create_part(organization: org, category: category)

    sign_in user
    assert_difference -> { Category.count } => -1 do
      delete category_path(category), params: { target_category_id: target.id }
    end

    assert_redirected_to categories_path
    assert_equal target.id, part.reload.category_id
    assert_not Category.exists?(category.id)
  end

  test "destroy also reassigns parts from subcategories that cascade-delete" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives")
    child = create_category(organization: org, name: "Resistors", parent: parent)
    target = create_category(organization: org, name: "Actives")
    parent_part = create_part(organization: org, category: parent)
    child_part = create_part(organization: org, category: child)

    sign_in user
    assert_difference -> { Category.count } => -2 do
      delete category_path(parent), params: { target_category_id: target.id }
    end

    assert_equal target.id, parent_part.reload.category_id
    assert_equal target.id, child_part.reload.category_id
  end

  test "destroy refuses a target inside the subtree being deleted" do
    user = create_user
    org = user.organizations.first
    parent = create_category(organization: org, name: "Passives")
    child = create_category(organization: org, name: "Resistors", parent: parent)
    create_part(organization: org, category: parent)

    sign_in user
    assert_no_difference "Category.count" do
      delete category_path(parent), params: { target_category_id: child.id }
    end

    assert Category.exists?(parent.id)
  end

  test "destroy ignores a target from another organization" do
    user = create_user
    org = user.organizations.first
    other_org = create_organization
    category = create_category(organization: org)
    create_part(organization: org, category: category)
    foreign_target = create_category(organization: other_org)

    sign_in user
    assert_no_difference "Category.count" do
      delete category_path(category), params: { target_category_id: foreign_target.id }
    end

    assert Category.exists?(category.id)
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
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

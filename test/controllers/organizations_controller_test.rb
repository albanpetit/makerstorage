require "test_helper"

class OrganizationsControllerTest < ActionDispatch::IntegrationTest
  test "destroy requires authentication" do
    org = create_organization
    delete organization_path(org)
    assert_redirected_to new_user_session_path
  end

  test "an owner can delete an organization they belong to" do
    user = create_user
    personal = user.organizations.first
    other = create_organization(name: "Second Org")
    OrganizationMembership.create!(organization: other, user: user, role: "owner")

    sign_in user
    assert_difference -> { Organization.count }, -1 do
      delete organization_path(other)
    end

    assert_redirected_to root_path
    assert_not Organization.exists?(other.id)
    assert Organization.exists?(personal.id)
  end

  test "a non-owner member cannot delete the organization" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    delete organization_path(org)

    assert Organization.exists?(org.id)
  end

  test "a user cannot delete their only organization" do
    user = create_user
    org = user.organizations.first

    sign_in user
    assert_no_difference -> { Organization.count } do
      delete organization_path(org)
    end

    assert Organization.exists?(org.id)
  end

  test "destroy is a no-op for an organization the user does not belong to" do
    user = create_user
    stranger_org = create_organization(name: "Not Mine")

    sign_in user
    assert_no_difference -> { Organization.count } do
      delete organization_path(stranger_org)
    end

    assert Organization.exists?(stranger_org.id)
  end

  test "create requires authentication" do
    post organizations_path, params: { organization: { name: "Nope" } }
    assert_redirected_to new_user_session_path
  end

  test "create makes an organization, adds the user as owner, and switches to it" do
    user = create_user

    sign_in user
    assert_difference -> { Organization.count }, 1 do
      post organizations_path, params: { organization: { name: "New Fablab" } }
    end

    assert_redirected_to root_path
    org = Organization.find_by(name: "New Fablab")
    assert user.owner_of?(org)
    assert org.organization_memberships.owners.active.exists?(user: user)

    follow_redirect!
    current_org = inertia_props.dig("auth", "current_organization")
    assert_equal org.id, current_org["id"]
  end

  test "create rejects a blank name with a namespaced error and creates nothing" do
    user = create_user

    sign_in user
    assert_no_difference -> { Organization.count } do
      post organizations_path, params: { organization: { name: "" } }
    end

    follow_redirect!
    assert inertia_props.dig("errors", "organization.name").present?
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

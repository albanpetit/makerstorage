require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get members_path
    assert_redirected_to new_user_session_path
  end

  test "index serializes members scoped to the current organization" do
    user = create_user
    org = user.organizations.first
    teammate = create_user(email: "teammate@example.com", firstname: "Lea", lastname: "Marchand")
    OrganizationMembership.create!(organization: org, user: teammate, role: "member")

    sign_in user
    get members_path
    assert_response :success

    members = inertia_props["members"]
    you = members.find { |m| m["email"] == user.email }
    teammate_json = members.find { |m| m["email"] == "teammate@example.com" }
    assert you["is_you"]
    assert_equal "owner", you["role"]
    assert_not teammate_json["is_you"]
    assert_equal "member", teammate_json["role"]
    assert_equal "Lea Marchand", teammate_json["name"]
  end

  test "index does not leak another organization's members" do
    user = create_user
    other_org = create_organization
    other_user = create_user(email: "other@example.com")
    OrganizationMembership.create!(organization: other_org, user: other_user, role: "owner")

    sign_in user
    get members_path
    assert_response :success

    emails = inertia_props["members"].map { |m| m["email"] }
    assert_not_includes emails, "other@example.com"
  end

  test "create adds an existing user to the organization" do
    user = create_user
    org = user.organizations.first
    invitee = create_user(email: "invitee@example.com")

    sign_in user
    assert_difference -> { OrganizationMembership.count } => 1 do
      post members_path, params: { member: { email: "invitee@example.com", role: "member" } }
    end

    assert_redirected_to members_path
    membership = org.organization_memberships.find_by(user: invitee)
    assert_equal "member", membership.role
    assert_not_nil membership.invitation_accepted_at
  end

  test "create fails when no account exists for that email" do
    user = create_user

    sign_in user
    assert_no_difference "OrganizationMembership.count" do
      post members_path, params: { member: { email: "ghost@example.com", role: "member" } }
    end

    assert_redirected_to members_path
    follow_redirect!
    assert_match(/No account found/, flash[:alert])
  end

  test "create fails when the user is already a member" do
    user = create_user
    org = user.organizations.first
    teammate = create_user(email: "teammate@example.com")
    OrganizationMembership.create!(organization: org, user: teammate, role: "viewer")

    sign_in user
    assert_no_difference "OrganizationMembership.count" do
      post members_path, params: { member: { email: "teammate@example.com", role: "member" } }
    end

    assert_redirected_to members_path
    follow_redirect!
    assert_match(/already a member/, flash[:alert])
  end

  test "update changes a member's role" do
    user = create_user
    org = user.organizations.first
    teammate = create_user(email: "teammate@example.com")
    membership = OrganizationMembership.create!(organization: org, user: teammate, role: "viewer")

    sign_in user
    patch member_path(membership), params: { member: { role: "admin" } }

    assert_redirected_to members_path
    assert_equal "admin", membership.reload.role
  end

  test "update refuses to demote the last owner" do
    user = create_user
    org = user.organizations.first
    membership = org.organization_memberships.find_by(user: user)

    sign_in user
    patch member_path(membership), params: { member: { role: "member" } }

    assert_redirected_to members_path
    assert_equal "owner", membership.reload.role
  end

  test "destroy removes a member" do
    user = create_user
    org = user.organizations.first
    teammate = create_user(email: "teammate@example.com")
    membership = OrganizationMembership.create!(organization: org, user: teammate, role: "member")

    sign_in user
    assert_difference -> { OrganizationMembership.count } => -1 do
      delete member_path(membership)
    end

    assert_redirected_to members_path
  end

  test "destroy refuses to remove the last owner" do
    user = create_user
    org = user.organizations.first
    membership = org.organization_memberships.find_by(user: user)

    sign_in user
    assert_no_difference "OrganizationMembership.count" do
      delete member_path(membership)
    end

    assert_redirected_to members_path
  end

  test "create is forbidden for a non-admin member" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: org, user: member, role: "member")
    invitee = create_user(email: "invitee@example.com")

    sign_in member
    assert_no_difference "OrganizationMembership.count" do
      post members_path, params: { member: { email: "invitee@example.com", role: "owner" } }
    end

    assert_redirected_to root_path
  end

  test "update is forbidden for a non-admin member, preventing role self-escalation" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    membership = OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    patch member_path(membership), params: { member: { role: "owner" } }

    assert_redirected_to root_path
    assert_equal "member", membership.reload.role
  end

  test "destroy is forbidden for a non-admin member" do
    owner = create_user
    org = owner.organizations.first
    member = create_user(email: "member@example.com")
    teammate = create_user(email: "teammate@example.com")
    membership = OrganizationMembership.create!(organization: org, user: member, role: "member")
    OrganizationMembership.create!(organization: org, user: teammate, role: "viewer")

    sign_in member
    assert_no_difference "OrganizationMembership.count" do
      delete member_path(OrganizationMembership.find_by(organization: org, user: teammate))
    end

    assert_redirected_to root_path
  end

  test "admin cannot invite a new owner" do
    owner = create_user
    org = owner.organizations.first
    admin = create_user(email: "admin@example.com")
    OrganizationMembership.create!(organization: org, user: admin, role: "admin")
    create_user(email: "invitee@example.com")

    sign_in admin
    assert_no_difference "OrganizationMembership.count" do
      post members_path, params: { member: { email: "invitee@example.com", role: "owner" } }
    end

    assert_redirected_to members_path
    follow_redirect!
    assert_match(/Only an owner/, flash[:alert])
  end

  test "admin cannot promote a member to owner" do
    owner = create_user
    org = owner.organizations.first
    admin = create_user(email: "admin@example.com")
    OrganizationMembership.create!(organization: org, user: admin, role: "admin")
    teammate = create_user(email: "teammate@example.com")
    membership = OrganizationMembership.create!(organization: org, user: teammate, role: "member")

    sign_in admin
    patch member_path(membership), params: { member: { role: "owner" } }

    assert_redirected_to members_path
    assert_equal "member", membership.reload.role
  end

  test "admin cannot escalate itself to owner" do
    owner = create_user
    org = owner.organizations.first
    admin = create_user(email: "admin@example.com")
    membership = OrganizationMembership.create!(organization: org, user: admin, role: "admin")

    sign_in admin
    patch member_path(membership), params: { member: { role: "owner" } }

    assert_redirected_to members_path
    assert_equal "admin", membership.reload.role
  end

  test "admin cannot demote an existing owner" do
    owner = create_user
    org = owner.organizations.first
    admin = create_user(email: "admin@example.com")
    OrganizationMembership.create!(organization: org, user: admin, role: "admin")
    second_owner = create_user(email: "owner2@example.com")
    membership = OrganizationMembership.create!(organization: org, user: second_owner, role: "owner")

    sign_in admin
    patch member_path(membership), params: { member: { role: "admin" } }

    assert_redirected_to members_path
    assert_equal "owner", membership.reload.role
  end

  test "admin cannot remove an existing owner" do
    owner = create_user
    org = owner.organizations.first
    admin = create_user(email: "admin@example.com")
    OrganizationMembership.create!(organization: org, user: admin, role: "admin")
    second_owner = create_user(email: "owner2@example.com")
    membership = OrganizationMembership.create!(organization: org, user: second_owner, role: "owner")

    sign_in admin
    assert_no_difference "OrganizationMembership.count" do
      delete member_path(membership)
    end

    assert_redirected_to members_path
    assert_match(/Only an owner/, flash[:alert])
  end

  test "owner can remove another owner" do
    owner = create_user
    org = owner.organizations.first
    second_owner = create_user(email: "owner2@example.com")
    membership = OrganizationMembership.create!(organization: org, user: second_owner, role: "owner")

    sign_in owner
    assert_difference -> { OrganizationMembership.count } => -1 do
      delete member_path(membership)
    end

    assert_redirected_to members_path
  end

  test "owner can invite a new owner" do
    owner = create_user
    org = owner.organizations.first
    create_user(email: "invitee@example.com")

    sign_in owner
    assert_difference -> { OrganizationMembership.count } => 1 do
      post members_path, params: { member: { email: "invitee@example.com", role: "owner" } }
    end

    assert_redirected_to members_path
    invitee_membership = org.organization_memberships.find_by(user: User.find_by(email: "invitee@example.com"))
    assert_equal "owner", invitee_membership.role
  end

  test "owner can promote a member to owner" do
    owner = create_user
    org = owner.organizations.first
    teammate = create_user(email: "teammate@example.com")
    membership = OrganizationMembership.create!(organization: org, user: teammate, role: "member")

    sign_in owner
    patch member_path(membership), params: { member: { role: "owner" } }

    assert_redirected_to members_path
    assert_equal "owner", membership.reload.role
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

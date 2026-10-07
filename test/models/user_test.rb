require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "signup creates a personal organization owned by the user" do
    user = create_user(firstname: "Grace", lastname: "Hopper")

    org = user.organizations.first
    assert_equal "Grace's Organization", org.name
    assert org.personal?
    assert user.owner_of?(org)
  end

  test "personal_organization resolves by the personal flag even after a rename" do
    user = create_user(firstname: "Grace", lastname: "Hopper")
    org = user.organizations.first
    org.update!(name: "Renamed Space")

    assert_equal org, user.personal_organization
  end

  test "writer_of? is true for owner, admin, and member roles" do
    %w[owner admin member].each do |role|
      user = create_user(email: "#{role}_#{SecureRandom.hex(4)}@example.com")
      org = create_organization
      OrganizationMembership.create!(organization: org, user: user, role: role)
      assert user.writer_of?(org), "expected #{role} to be a writer"
    end
  end

  test "writer_of? is false for viewers" do
    user = create_user
    org = create_organization
    OrganizationMembership.create!(organization: org, user: user, role: "viewer")
    assert_not user.writer_of?(org)
  end

  test "writer_of? is false for a non-member" do
    user = create_user
    org = create_organization
    assert_not user.writer_of?(org)
  end

  test "destroy keeps the stock ledger and invitations, clearing the user reference" do
    user = create_user
    org = user.organizations.first
    # A second owner, so the sole-owner guard doesn't block removing `user`.
    co_owner = create_user
    OrganizationMembership.create!(organization: org, user: co_owner, role: "owner")
    invitee = create_user
    invitation = OrganizationMembership.create!(organization: org, user: invitee, role: "member", invited_by: user)
    movement = org.stock_movements.create!(part: create_part(organization: org),
                                           storage_location: create_storage_location(organization: org),
                                           movement_type: "in", quantity_delta: 3, user: user)

    assert user.destroy
    assert_nil movement.reload.user_id
    assert_nil invitation.reload.invited_by_id
  end

  test "a deactivated membership grants no access" do
    owner = create_user
    org = owner.organizations.first
    member = create_user
    membership = OrganizationMembership.create!(organization: org, user: member, role: "admin")
    assert member.writer_of?(org)

    membership.deactivate!

    assert_not member.member_of_organization?(org.id)
    assert_not member.writer_of?(org)
    assert_not member.admin_of?(org)
    assert_nil member.role_in(org)
    assert_not_includes member.organizations, org
  end

  test "organizations_where_owner only lists organizations the user owns" do
    owner = create_user
    member = create_user
    shared = owner.organizations.first
    OrganizationMembership.create!(organization: shared, user: member, role: "member")

    assert_includes owner.organizations_where_owner, shared
    assert_not_includes member.organizations_where_owner, shared
    assert_includes member.organizations_where_owner, member.personal_organization
    assert_not_includes member.organizations_where_admin, shared
  end
end

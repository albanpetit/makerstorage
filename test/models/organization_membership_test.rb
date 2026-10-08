require "test_helper"

class OrganizationMembershipTest < ActiveSupport::TestCase
  def setup
    @org = create_organization
    @user = User.create!(firstname: "M", lastname: "T", email: "member_test@example.com", password: "password123")
  end

  test "accepts owner, admin, member, and viewer roles" do
    %w[owner admin member viewer].each do |role|
      membership = OrganizationMembership.new(organization: @org, user: @user, role: role)
      assert membership.valid?, "expected role #{role} to be valid"
    end
  end

  test "rejects an unknown role" do
    membership = OrganizationMembership.new(organization: @org, user: @user, role: "superadmin")
    assert_not membership.valid?
    assert_includes membership.errors[:role], "is not included in the list"
  end

  test "role predicate methods" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "viewer")
    assert membership.viewer?
    assert_not membership.owner?
    assert_not membership.admin?
    assert_not membership.member?
  end

  test "prevents destroying the last active owner" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "owner")

    assert_not membership.destroy
    assert_includes membership.errors[:base], "Organization must have at least one active owner"
    assert OrganizationMembership.exists?(membership.id)
  end

  test "allows destroying an owner when another active owner remains" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "owner")
    other_user = User.create!(firstname: "O", lastname: "2", email: "owner_2@example.com", password: "password123")
    OrganizationMembership.create!(organization: @org, user: other_user, role: "owner")

    assert membership.destroy
  end

  test "prevents changing the last owner's role away from owner" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "owner")

    assert_not membership.update(role: "member")
    assert_includes membership.errors[:role], "Organization must have at least one active owner"
  end

  test "generates an invitation token only when invited" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "member")
    assert_nil membership.invitation_token

    invited_user = User.create!(firstname: "I", lastname: "N", email: "invited@example.com", password: "password123")
    invited = OrganizationMembership.create!(
      organization: @org, user: invited_user, role: "member", invitation_sent_at: Time.current
    )
    assert_not_nil invited.invitation_token
  end

  test "pending_invitation? and accept_invitation!" do
    invited_user = User.create!(firstname: "I", lastname: "N", email: "invited2@example.com", password: "password123")
    membership = OrganizationMembership.create!(
      organization: @org, user: invited_user, role: "member", invitation_sent_at: Time.current
    )

    assert membership.pending_invitation?
    assert_not membership.accepted?

    membership.accept_invitation!
    assert membership.accepted?
    assert_not membership.pending_invitation?
  end

  test "activate! and deactivate!" do
    membership = OrganizationMembership.create!(organization: @org, user: @user, role: "member")
    assert membership.active?

    membership.deactivate!
    assert_not membership.reload.active?

    membership.activate!
    assert membership.reload.active?
  end

  test "the last active owner can't be deactivated" do
    owner = create_user
    membership = owner.organizations.first.organization_memberships.find_by(user: owner)

    assert_not membership.update(active: false)
    assert_includes membership.errors[:active].join, "active owner"
  end

  test "an owner can be deactivated while another owner remains active" do
    owner = create_user
    org = owner.organizations.first
    OrganizationMembership.create!(organization: org, user: create_user, role: "owner")
    membership = org.organization_memberships.find_by(user: owner)

    assert membership.update(active: false)
  end

  test "an inactive owner can be removed while one active owner remains" do
    OrganizationMembership.create!(organization: @org, user: @user, role: "owner")
    other_user = User.create!(firstname: "O", lastname: "2", email: "owner_2@example.com", password: "password123")
    inactive = OrganizationMembership.create!(organization: @org, user: other_user, role: "owner", active: false)

    assert inactive.destroy
  end

  test "an inactive owner can be demoted while one active owner remains" do
    OrganizationMembership.create!(organization: @org, user: @user, role: "owner")
    other_user = User.create!(firstname: "O", lastname: "2", email: "owner_2@example.com", password: "password123")
    inactive = OrganizationMembership.create!(organization: @org, user: other_user, role: "owner", active: false)

    assert inactive.update(role: "member")
  end

  test "the sole active owner can't be demoted even when inactive owners remain" do
    active = OrganizationMembership.create!(organization: @org, user: @user, role: "owner")
    other_user = User.create!(firstname: "O", lastname: "2", email: "owner_2@example.com", password: "password123")
    OrganizationMembership.create!(organization: @org, user: other_user, role: "owner", active: false)

    assert_not active.update(role: "admin")
    assert_not active.reload.destroy
  end
end

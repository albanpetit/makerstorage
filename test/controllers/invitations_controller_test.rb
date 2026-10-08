require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    @org = Organization.create!(name: "Fablab")
    OrganizationMembership.create!(organization: @org, user: @admin, role: "owner")
    @invitee = create_user
    @invitation = OrganizationMembership.create!(
      organization: @org, user: @invitee, role: "member", invited_by: @admin, invitation_sent_at: Time.current
    )
  end

  test "a pending invitation grants no access" do
    sign_in @invitee
    post switch_organization_path(@org)

    assert_not @invitee.member_of_organization?(@org.id)
    assert_not_includes @invitee.organizations, @org
    assert_match(/not found/i, flash[:alert])
  end

  test "the profile lists the user's pending invitations" do
    sign_in @invitee
    get profile_path

    invitation = inertia_props["invitations"].sole
    assert_equal "Fablab", invitation["organization_name"]
    assert_equal "member", invitation["role"]
    assert_equal 1, inertia_props.dig("auth", "pending_invitations_count")
  end

  test "accepting joins the organization and switches to it" do
    sign_in @invitee
    post accept_invitation_path(@invitation)

    assert_redirected_to root_path
    assert @invitation.reload.accepted?
    assert @invitee.member_of_organization?(@org.id)
    assert_equal @org.id, session[:current_organization_id]
  end

  test "declining removes the invitation" do
    sign_in @invitee
    assert_difference -> { OrganizationMembership.count } => -1 do
      delete decline_invitation_path(@invitation)
    end

    assert_redirected_to profile_path
    assert_not @invitee.member_of_organization?(@org.id)
  end

  test "nobody else can answer the invitation" do
    sign_in @admin

    post accept_invitation_path(@invitation)
    assert_response :not_found
    assert @invitation.reload.pending_invitation?
  end

  test "an accepted invitation can't be declined through this endpoint" do
    @invitation.accept_invitation!
    sign_in @invitee

    assert_no_difference -> { OrganizationMembership.count } do
      delete decline_invitation_path(@invitation)
    end
    assert_response :not_found
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

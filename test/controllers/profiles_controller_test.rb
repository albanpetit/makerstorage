require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get profile_path
    assert_redirected_to new_user_session_path
  end

  test "show renders the current user's details" do
    user = create_user(firstname: "Ada", lastname: "Lovelace", email: "ada@example.com")

    sign_in user
    get profile_path
    assert_response :success

    profile = inertia_props["user"]
    assert_equal "Ada", profile["firstname"]
    assert_equal "Lovelace", profile["lastname"]
    assert_equal "ada@example.com", profile["email"]
  end

  test "update saves name and email changes" do
    user = create_user

    sign_in user
    patch profile_path, params: { user: {
      firstname: "New", lastname: "Name", email: "new-email@example.com", current_password: "password123"
    } }

    assert_redirected_to profile_path
    assert_match(/confirm new-email@example.com/i, flash[:notice])
    user.reload
    assert_equal "New", user.firstname
    assert_equal "Name", user.lastname
    # The new address only applies once its owner confirms it.
    assert_equal "new-email@example.com", user.unconfirmed_email
    assert_not_equal "new-email@example.com", user.email

    user.confirm
    assert_equal "new-email@example.com", user.reload.email
  end

  test "an email change applies at once when email verification is off" do
    user = create_user
    sign_in user

    with_email_verification(false) do
      patch profile_path, params: { user: { email: "direct@example.com", current_password: "password123" } }
    end

    assert_equal "direct@example.com", user.reload.email
    assert_nil user.unconfirmed_email
  end

  test "show reports an unconfirmed address and hides invitations until it's confirmed" do
    user = create_user(confirmed_at: nil)
    org = create_organization(name: "Hackerspace")
    OrganizationMembership.create!(organization: org, user: user, role: "member", invitation_sent_at: Time.current)

    sign_in user
    get profile_path

    assert_equal false, inertia_props.dig("user", "email_confirmed")
    assert_empty inertia_props["invitations"]
    assert_equal 0, inertia_props.dig("auth", "pending_invitations_count")

    user.confirm
    get profile_path
    assert_equal [ "Hackerspace" ], inertia_props["invitations"].map { |i| i["organization_name"] }
  end

  test "changing the email without the current password is refused" do
    user = create_user(email: "keep@example.com")

    sign_in user
    patch profile_path, params: { user: { email: "attacker@example.com" } }

    assert_equal "keep@example.com", user.reload.email
    follow_redirect!
    assert inertia_props.dig("errors", "user.current_password").present?
  end

  test "changing the email with a wrong current password is refused" do
    user = create_user(email: "keep@example.com")

    sign_in user
    patch profile_path, params: { user: { email: "attacker@example.com", current_password: "guess" } }

    assert_equal "keep@example.com", user.reload.email
    assert_match(/current password/i, flash[:alert])
  end

  test "name changes and a case-only email edit don't need the password" do
    user = create_user(email: "keep@example.com")

    sign_in user
    patch profile_path, params: { user: { firstname: "Renamed", lastname: "User", email: "KEEP@example.com" } }

    assert_equal "Renamed", user.reload.firstname
    assert_equal "keep@example.com", user.email
  end

  test "update rejects an invalid email and reports namespaced errors" do
    user = create_user(email: "keep@example.com")

    sign_in user
    patch profile_path, params: { user: { email: "not-an-email", current_password: "password123" } }

    assert_redirected_to profile_path
    assert_equal "keep@example.com", user.reload.email
    follow_redirect!
    # Keys must be namespaced to match the nested `user` form on the frontend.
    assert inertia_props.dig("errors", "user.email").present?
  end

  test "update changes the password when the current password is correct" do
    user = create_user

    sign_in user
    patch profile_path, params: { user: {
      current_password: "password123",
      password: "new-password456",
      password_confirmation: "new-password456"
    } }

    assert_redirected_to profile_path
    assert user.reload.valid_password?("new-password456")
  end

  test "update rejects a password change with the wrong current password" do
    user = create_user

    sign_in user
    patch profile_path, params: { user: {
      current_password: "wrong-password",
      password: "new-password456",
      password_confirmation: "new-password456"
    } }

    assert_redirected_to profile_path
    assert_not user.reload.valid_password?("new-password456")
    assert user.valid_password?("password123")
  end

  test "wrong current passwords count toward the account lock and end the session" do
    user = create_user(email: "keep@example.com")

    sign_in user
    Devise.maximum_attempts.times do
      patch profile_path, params: { user: { email: "attacker@example.com", current_password: "guess" } }
    end

    user.reload
    assert user.access_locked?
    assert_equal "keep@example.com", user.email

    get profile_path
    assert_redirected_to new_user_session_path
  end

  test "a wrong current password on the password form counts as a failed attempt" do
    user = create_user

    sign_in user
    assert_difference -> { user.reload.failed_attempts }, 1 do
      patch profile_path, params: { user: { current_password: "wrong", password: "new-password456", password_confirmation: "new-password456" } }
    end
  end

  test "a blank current password isn't counted as a guess" do
    user = create_user

    sign_in user
    assert_no_difference -> { user.reload.failed_attempts } do
      patch profile_path, params: { user: { email: "other@example.com", current_password: "" } }
    end
  end

  test "changing the password sends a password-change notification" do
    user = create_user(email: "pw@example.com")

    sign_in user
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      patch profile_path, params: { user: {
        current_password: "password123",
        password: "new-password456",
        password_confirmation: "new-password456"
      } }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ user.email ], mail.to
    assert_match(/password/i, mail.subject)
  end

  test "changing the email warns the old address and asks the new one to confirm" do
    user = create_user(email: "old@example.com")

    sign_in user
    assert_difference -> { ActionMailer::Base.deliveries.size }, 2 do
      patch profile_path, params: { user: { email: "new@example.com", current_password: "password123" } }
    end

    notice, confirmation = ActionMailer::Base.deliveries.last(2)
    assert_equal [ "old@example.com" ], notice.to
    assert_match(/email/i, notice.subject)
    assert_equal [ "new@example.com" ], confirmation.to
    assert_match(/confirm/i, confirmation.subject)
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  test "show lists the user's organizations with their email notification choice" do
    user = create_user
    other = create_organization(name: "Aardvark Lab")
    other.organization_memberships.create!(user: user, role: "member", email_notifications: false)

    sign_in user
    get profile_path

    assert_equal true, inertia_props["email_notifications_available"]
    memberships = inertia_props["notification_memberships"]
    assert_equal [ "Aardvark Lab", user.organizations.find_by(personal: true).name ].sort_by(&:downcase),
                 memberships.map { |m| m["organization_name"] }
    assert_equal false, memberships.find { |m| m["organization_name"] == "Aardvark Lab" }["email_notifications"]
  end

  test "update_notifications opts the user out of one organization's digest" do
    user = create_user
    membership = user.active_organization_memberships.first

    sign_in user
    patch profile_notifications_path(membership), params: { email_notifications: false }

    assert_redirected_to profile_path
    assert_not membership.reload.email_notifications

    patch profile_notifications_path(membership), params: { email_notifications: true }
    assert membership.reload.email_notifications
  end

  test "update_notifications can't touch another user's membership" do
    user = create_user
    stranger = create_user
    membership = stranger.active_organization_memberships.first

    sign_in user
    patch profile_notifications_path(membership), params: { email_notifications: false }

    assert_response :not_found
    assert membership.reload.email_notifications
  end

  test "show lists the MCP URL and the apps connected to the inventory" do
    user = create_user
    org = user.organizations.first
    connect_mcp_client(user: user, organization: org, client: create_oauth_client(name: "Claude Code", redirect_uris: [ "http://localhost/callback" ]))
    # A consent nobody exchanged for tokens isn't a connected app.
    _verifier, challenge = pkce_pair
    client = create_oauth_client
    OauthAuthorization.grant!(client: client, user: user, organization: org, redirect_uri: client.redirect_uris.first, code_challenge: challenge)

    sign_in user
    get profile_path

    assert_equal "http://www.example.com/mcp", inertia_props["mcp_url"]
    app = inertia_props["connected_apps"].sole
    assert_equal [ "Claude Code", org.name ], [ app["name"], app["organization_name"] ]
    assert_equal [ false, true ], [ app["write"], app["can_write"] ]
  end

  test "update_connected_app turns changes on and off, never for a viewer or another user" do
    user = create_user
    connect_mcp_client(user: user, organization: user.organizations.first)
    authorization = user.oauth_authorizations.sole

    sign_in create_user
    patch profile_connected_app_path(authorization), params: { write: true }
    assert_response :not_found

    sign_in user
    patch profile_connected_app_path(authorization), params: { write: true }
    assert_redirected_to profile_path
    assert authorization.reload.can_write?

    patch profile_connected_app_path(authorization), params: { write: false }
    assert_equal "mcp:read", authorization.reload.scope

    viewed = create_organization
    OrganizationMembership.create!(organization: viewed, user: user, role: "viewer")
    connect_mcp_client(user: user, organization: viewed)
    viewer_grant = user.oauth_authorizations.find_by(organization: viewed)
    patch profile_connected_app_path(viewer_grant), params: { write: true }
    assert_redirected_to profile_path
    assert_equal "mcp:read", viewer_grant.reload.scope
  end

  test "revoke_connected_app disconnects an app, only for its own user" do
    user = create_user
    tokens = connect_mcp_client(user: user, organization: user.organizations.first)
    authorization = user.oauth_authorizations.sole

    sign_in create_user
    delete profile_connected_app_path(authorization)
    assert_response :not_found
    assert OauthAuthorization.authenticate(tokens[:access_token])

    sign_in user
    delete profile_connected_app_path(authorization)
    assert_redirected_to profile_path
    assert_nil OauthAuthorization.authenticate(tokens[:access_token])
  end
end

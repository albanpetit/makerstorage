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
end

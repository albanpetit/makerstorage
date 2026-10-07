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
    user.reload
    assert_equal "New", user.firstname
    assert_equal "Name", user.lastname
    assert_equal "new-email@example.com", user.email
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

  test "changing the email sends an email-changed notification" do
    user = create_user(email: "old@example.com")

    sign_in user
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      patch profile_path, params: { user: { email: "new@example.com", current_password: "password123" } }
    end

    assert_match(/email/i, ActionMailer::Base.deliveries.last.subject)
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

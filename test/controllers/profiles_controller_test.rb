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
      firstname: "New", lastname: "Name", email: "new-email@example.com"
    } }

    assert_redirected_to profile_path
    user.reload
    assert_equal "New", user.firstname
    assert_equal "Name", user.lastname
    assert_equal "new-email@example.com", user.email
  end

  test "update rejects an invalid email and reports namespaced errors" do
    user = create_user(email: "keep@example.com")

    sign_in user
    patch profile_path, params: { user: { email: "not-an-email" } }

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

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

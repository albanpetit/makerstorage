require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signing up creates the user and their personal organization" do
    assert_difference -> { User.count } => 1, -> { Organization.count } => 1 do
      post user_registration_path, params: { user: signup_params("new-maker@example.com") }
    end

    assert_redirected_to root_path
  end

  test "sign-ups are throttled per IP" do
    10.times { |i| sign_up("maker#{i}@example.com") }

    assert_no_difference -> { User.count } do
      sign_up("one-too-many@example.com")
    end
    assert_match(/too many sign-ups/i, flash[:alert])
  end

  private

  def sign_up(email)
    post user_registration_path, params: { user: signup_params(email) }
    # Each successful sign-up signs the user in; sign out so the next one is anonymous.
    delete destroy_user_session_path
  end

  def signup_params(email)
    { firstname: "Ada", lastname: "Lovelace", email: email, password: "password123", password_confirmation: "password123" }
  end
end

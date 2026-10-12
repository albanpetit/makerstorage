require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signing up creates the user and their personal organization" do
    assert_difference -> { User.count } => 1, -> { Organization.count } => 1 do
      post user_registration_path, params: { user: signup_params("new-maker@example.com") }
    end

    assert_redirected_to root_path
  end

  test "signing up signs in at once and mails a confirmation link" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post user_registration_path, params: { user: signup_params("confirm-me@example.com") }
    end

    assert_redirected_to root_path
    user = User.find_by!(email: "confirm-me@example.com")
    assert_not user.confirmed?
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "confirm-me@example.com" ], mail.to
    assert_match(%r{/confirm-email\?confirmation_token=[\w-]+}, mail.text_part.body.to_s)

    follow_redirect!
    assert_response :success, "an unconfirmed account can still use the app"
  end

  test "without email verification a new account is confirmed and gets no mail" do
    with_email_verification(false) do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        post user_registration_path, params: { user: signup_params("lan-maker@example.com") }
      end
    end

    assert User.find_by!(email: "lan-maker@example.com").confirmed?
  end

  test "a password shorter than 8 characters is rejected" do
    assert_no_difference -> { User.count } do
      post user_registration_path, params: { user: signup_params("short@example.com").merge(password: "1234567", password_confirmation: "1234567") }
    end
  end

  test "sign-ups are throttled per IP" do
    Users::RegistrationsController::RATE_LIMIT.times { |i| sign_up("maker#{i}@example.com") }

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

require "test_helper"

class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "requesting a reset delivers branded instructions to a known email" do
    user = create_user(email: "reset-me@example.com")

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_redirected_to new_user_session_path

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ user.email ], mail.to
    body = mail.html_part.body.to_s
    # End-to-end guard: the email renders and links to the app's custom reset
    # route with a token (the stock Devise edit_password_url doesn't exist here).
    assert_includes body, "/reset-password"
    # Devise tokens are URL-safe base64, so they can start with "-" or "_".
    assert_match(/reset_password_token=[\w-]+/, body)
  end

  test "requesting a reset for an unknown email sends no mail but answers the same" do
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post user_password_path, params: { user: { email: "nobody@example.com" } }
    end
    unknown_notice = flash[:notice]

    post user_password_path, params: { user: { email: create_user.email } }

    assert_redirected_to new_user_session_path
    assert_equal flash[:notice], unknown_notice, "known and unknown emails must get the same response"
  end

  test "a blank email is asked for again" do
    post user_password_path, params: { user: { email: "" } }

    assert_redirected_to new_user_password_path
    assert_match(/enter your email/i, flash[:alert])
  end

  test "resetting the password through the mailed link confirms the address" do
    user = create_user(confirmed_at: nil)
    token = user.send_reset_password_instructions

    put update_user_password_path, params: { user: { reset_password_token: token, password: "brand-new-pass1", password_confirmation: "brand-new-pass1" } }

    assert user.reload.confirmed?
  end

  test "a password reset doesn't apply an email change still awaiting confirmation" do
    user = create_user(email: "current@example.com")
    user.update!(email: "pending@example.com")
    token = user.send_reset_password_instructions

    put update_user_password_path, params: { user: { reset_password_token: token, password: "brand-new-pass1", password_confirmation: "brand-new-pass1" } }

    assert_equal "current@example.com", user.reload.email
    assert_equal "pending@example.com", user.unconfirmed_email
  end

  test "reset requests are throttled per IP" do
    Users::PasswordsController::RATE_LIMIT.times { post user_password_path, params: { user: { email: "nobody@example.com" } } }

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post user_password_path, params: { user: { email: create_user.email } }
    end
    assert_match(/too many reset requests/i, flash[:alert])
  end

  test "the forgot and reset password pages render" do
    get new_user_password_path
    assert_response :success

    get edit_user_password_path(reset_password_token: "abc")
    assert_response :success
    assert_includes response.body, "abc"
  end

  test "a reset with a bad token or mismatched passwords goes back to the form" do
    user = create_user
    token = user.send_reset_password_instructions

    put update_user_password_path, params: { user: { reset_password_token: "wrong", password: "brand-new-pass1", password_confirmation: "brand-new-pass1" } }
    assert_redirected_to edit_user_password_path(reset_password_token: "wrong")
    assert flash[:alert].present?

    put update_user_password_path, params: { user: { reset_password_token: token, password: "brand-new-pass1", password_confirmation: "other-pass-22" } }
    assert_redirected_to edit_user_password_path(reset_password_token: token)
    assert_not user.reload.valid_password?("brand-new-pass1")
  end

  test "a reset signs in, or sends to the sign-in page when sign-in after reset is off" do
    user = create_user
    put update_user_password_path, params: { user: { reset_password_token: user.send_reset_password_instructions, password: "brand-new-pass1", password_confirmation: "brand-new-pass1" } }
    assert_redirected_to root_path

    delete destroy_user_session_path
    previous = Devise.sign_in_after_reset_password
    Devise.sign_in_after_reset_password = false
    put update_user_password_path, params: { user: { reset_password_token: user.send_reset_password_instructions, password: "brand-new-pass2", password_confirmation: "brand-new-pass2" } }
    assert_redirected_to new_user_session_path
    assert user.reload.valid_password?("brand-new-pass2")
  ensure
    Devise.sign_in_after_reset_password = previous unless previous.nil?
  end
end

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
    assert_match(/reset_password_token=\w/, body)
  end

  test "requesting a reset for an unknown email sends no mail" do
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post user_password_path, params: { user: { email: "nobody@example.com" } }
    end
    assert_redirected_to new_user_password_path
  end
end

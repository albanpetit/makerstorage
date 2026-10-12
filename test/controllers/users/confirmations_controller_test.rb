require "test_helper"

class Users::ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  test "the mailed link confirms the account" do
    user = create_user(confirmed_at: nil)
    token = mailed_token { user.send_confirmation_instructions }

    get user_confirmation_path(confirmation_token: token)

    assert_redirected_to new_user_session_path
    assert_match(/is confirmed/i, flash[:notice])
    assert user.reload.confirmed?
  end

  test "the mailed link applies a pending email change" do
    user = create_user(email: "before@example.com")
    token = mailed_token { user.update!(email: "after@example.com") }
    sign_in user

    get user_confirmation_path(confirmation_token: token)

    assert_redirected_to profile_path
    assert_equal "after@example.com", user.reload.email
    assert_nil user.unconfirmed_email
  end

  test "an unknown or expired link is refused" do
    user = create_user(confirmed_at: nil)
    token = mailed_token { user.send_confirmation_instructions }

    get user_confirmation_path(confirmation_token: "not-a-token")
    assert_match(/invalid or has expired/i, flash[:alert])

    travel Devise.confirm_within + 1.minute do
      get user_confirmation_path(confirmation_token: token)
    end
    assert_match(/invalid or has expired/i, flash[:alert])
    assert_not user.reload.confirmed?
  end

  test "a signed-in user can have the confirmation mail sent again" do
    user = create_user(confirmed_at: nil)
    sign_in user

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post resend_user_confirmation_path
    end
    assert_redirected_to profile_path
    assert_equal [ user.email ], ActionMailer::Base.deliveries.last.to
  end

  test "resending goes to the new address of a pending email change" do
    user = create_user(email: "before@example.com")
    user.update!(email: "after@example.com")
    sign_in user

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post resend_user_confirmation_path
    end
    assert_equal [ "after@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "resending to a confirmed address sends nothing" do
    sign_in create_user

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post resend_user_confirmation_path
    end
    assert_match(/already confirmed/i, flash[:notice])
  end

  test "resending needs a signed-in user" do
    post resend_user_confirmation_path
    assert_redirected_to new_user_session_path
  end

  test "resends are throttled per IP" do
    user = create_user(confirmed_at: nil)
    sign_in user
    Users::ConfirmationsController::RATE_LIMIT.times { post resend_user_confirmation_path }

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post resend_user_confirmation_path
    end
    assert_match(/too many confirmation emails/i, flash[:alert])
  end

  private

  # The raw token only exists in the mail (the database keeps it for lookup).
  def mailed_token
    yield
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/confirmation_token=([\w-]+)/, 1]
  end
end

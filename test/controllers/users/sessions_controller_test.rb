require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "locksmith@example.com")
  end

  test "valid credentials sign the user in" do
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    assert_redirected_to root_path
  end

  test "a wrong password gets the generic invalid message" do
    post user_session_path, params: { user: { email: @user.email, password: "nope" } }

    assert_redirected_to new_user_session_path
    assert_match(/invalid/i, flash[:alert])
  end

  test "repeated failures lock the account, even against the right password" do
    Devise.maximum_attempts.times { fail_sign_in }
    assert @user.reload.access_locked?

    clear_rate_limits
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    assert_redirected_to new_user_session_path
    assert_match(/locked for 15 minutes/i, flash[:alert])
  end

  test "a locked account unlocks itself after the unlock window" do
    Devise.maximum_attempts.times { fail_sign_in }
    clear_rate_limits

    travel Devise.unlock_in + 1.minute do
      post user_session_path, params: { user: { email: @user.email, password: "password123" } }
      assert_redirected_to root_path
    end
  end

  test "a class signing in together from one IP isn't throttled" do
    15.times do |i|
      member = create_user(email: "student#{i}@example.com")
      post user_session_path, params: { user: { email: member.email, password: "password123" } }
      assert_redirected_to root_path
      delete destroy_user_session_path
    end
  end

  test "sign-in attempts are throttled per IP across accounts" do
    Users::SessionsController::RATE_LIMIT.times do |i|
      post user_session_path, params: { user: { email: "spray#{i}@example.com", password: "guess" } }
    end

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    assert_redirected_to new_user_session_path
    assert_match(/too many sign-in attempts/i, flash[:alert])
  end

  private

  def fail_sign_in
    post user_session_path, params: { user: { email: @user.email, password: "wrong" } }
  end

  def clear_rate_limits
    Rails.application.config.x.rate_limit_store.clear
  end
end

require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  setup do
    @user = create_user(email: "reset@example.com")
  end

  test "reset_password_instructions renders with branded sender and both parts" do
    mail = Devise::Mailer.reset_password_instructions(@user, "sometoken")

    # The from address is env-driven (MAILER_SENDER); assert it matches the
    # configured sender rather than a hardcoded, instance-specific value.
    expected_from = Mail::Address.new(Devise.mailer_sender).address
    assert_equal [ expected_from ], mail.from
    assert_equal [ @user.email ], mail.to
    assert mail.subject.present?
    # Multipart: layout provides both html and text shells.
    assert mail.html_part.present?, "expected an HTML part"
    assert mail.text_part.present?, "expected a text part"
  end

  test "reset_password_instructions links to the app's custom reset route with the token" do
    mail = Devise::Mailer.reset_password_instructions(@user, "sometoken")
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    # Regression guard: the stock Devise template uses `edit_password_url`,
    # which doesn't exist here because default password routes are skipped.
    [ html, text ].each do |body|
      assert_includes body, "/reset-password"
      assert_includes body, "reset_password_token=sometoken"
    end
    assert_includes html, "Reset password"
    # Brand chrome from layouts/mailer must wrap the body (guards against Devise
    # not inheriting ApplicationMailer's layout). The footer line only lives in
    # the layout, not the reset template itself.
    assert_includes html, "Electronics-parts inventory for makerspaces"
    assert_includes text, "Electronics-parts inventory for makerspaces"
  end

  test "password_change and email_changed notifications render" do
    change = Devise::Mailer.password_change(@user)
    assert_includes change.html_part.body.to_s, "password"

    changed = Devise::Mailer.email_changed(@user)
    assert_includes changed.html_part.body.to_s, @user.email
  end
end

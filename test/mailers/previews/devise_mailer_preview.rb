# Preview branded Devise emails at http://localhost:3000/rails/mailers/devise_mailer
class DeviseMailerPreview < ActionMailer::Preview
  # http://localhost:3000/rails/mailers/devise_mailer/reset_password_instructions
  def reset_password_instructions
    Devise::Mailer.reset_password_instructions(preview_user, "faketoken-preview-1234567890")
  end

  # http://localhost:3000/rails/mailers/devise_mailer/password_change
  def password_change
    Devise::Mailer.password_change(preview_user)
  end

  # http://localhost:3000/rails/mailers/devise_mailer/email_changed
  def email_changed
    Devise::Mailer.email_changed(preview_user)
  end

  private

  def preview_user
    User.first || User.new(email: "maker@example.com", firstname: "Maker", lastname: "Space")
  end
end

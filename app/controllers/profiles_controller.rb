# frozen_string_literal: true

class ProfilesController < ApplicationController
  include Auth

  def show
    render inertia: "profile/index", props: {
      user: {
        firstname: current_user.firstname,
        lastname: current_user.lastname,
        email: current_user.email
      }
    }
  end

  def update
    password_change? ? update_password : update_details
  end

  private

  # The password form always sends a `password` field (even blank); the details
  # form never does, though it may carry `current_password` for an email change.
  def password_change?
    params[:user].respond_to?(:key?) && params[:user].key?(:password)
  end

  def update_details
    current_user.assign_attributes(details_params)
    # Devise normalizes the email on validation; do it now so a case-only edit
    # doesn't count as a change below.
    current_user.email = current_user.email.to_s.strip.downcase

    # The sign-in email is what password resets go to, so changing it takes the
    # current password — otherwise a hijacked session could redirect resets to
    # an attacker's inbox and take the account over.
    if current_user.will_save_change_to_email? && !current_user.valid_password?(params.dig(:user, :current_password).to_s)
      current_user.errors.add(:current_password, params.dig(:user, :current_password).blank? ? :blank : :invalid)
      return redirect_to profile_path, inertia: { errors: inertia_errors(current_user, as: :user) },
        alert: "Enter your current password to change your email."
    end

    if current_user.save
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      redirect_to profile_path, inertia: { errors: inertia_errors(current_user, as: :user) }, alert: "Failed to update profile."
    end
  end

  def update_password
    if current_user.update_with_password(password_params)
      # Changing the password rotates the Devise auth token, which would sign
      # the user out — keep the current session alive.
      bypass_sign_in(current_user)
      redirect_to profile_path, notice: "Password updated successfully."
    else
      redirect_to profile_path, inertia: { errors: inertia_errors(current_user, as: :user) }, alert: "Failed to update password."
    end
  end

  def details_params
    params.require(:user).permit(:firstname, :lastname, :email)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end

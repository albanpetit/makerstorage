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

  # A password change is any request that carries password fields; otherwise
  # we treat it as a plain details (name/email) update.
  def password_change?
    params.dig(:user, :password).present? || params.dig(:user, :current_password).present?
  end

  def update_details
    if current_user.update(details_params)
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

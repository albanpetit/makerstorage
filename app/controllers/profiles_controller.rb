# frozen_string_literal: true

class ProfilesController < ApplicationController
  include Auth

  def show
    render inertia: "profile/index", props: {
      user: {
        firstname: current_user.firstname,
        lastname: current_user.lastname,
        email: current_user.email
      },
      invitations: current_user.pending_invitations.includes(:organization, :invited_by).order(:invitation_sent_at).map do |invitation|
        inviter = invitation.invited_by
        {
          id: invitation.id,
          organization_name: invitation.organization.name,
          role: invitation.role,
          invited_by: inviter && ("#{inviter.firstname} #{inviter.lastname}".strip.presence || inviter.email),
          sent_at: invitation.invitation_sent_at.iso8601
        }
      end
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
    if current_user.will_save_change_to_email? && !current_password_valid?(params.dig(:user, :current_password))
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
    unless current_password_valid?(password_params[:current_password])
      current_user.errors.add(:current_password, password_params[:current_password].blank? ? :blank : :invalid)
      return redirect_to profile_path, inertia: { errors: inertia_errors(current_user, as: :user) }, alert: "Failed to update password."
    end

    if current_user.update_with_password(password_params)
      # Changing the password rotates the Devise auth token, which would sign
      # the user out — keep the current session alive.
      bypass_sign_in(current_user)
      redirect_to profile_path, notice: "Password updated successfully."
    else
      redirect_to profile_path, inertia: { errors: inertia_errors(current_user, as: :user) }, alert: "Failed to update password."
    end
  end

  # A wrong current password counts as a failed sign-in (Devise :lockable), so a
  # hijacked session can't guess it any faster than the login form allows: the
  # account locks after the same number of misses and the session then ends.
  # Checked on a fresh copy because a miss saves the user, and current_user may
  # hold the unsaved profile edits being guarded. A blank field isn't a guess.
  def current_password_valid?(password)
    return false if password.blank?

    User.find(current_user.id).valid_for_authentication? { current_user.valid_password?(password) }
  end

  def details_params
    params.require(:user).permit(:firstname, :lastname, :email)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end

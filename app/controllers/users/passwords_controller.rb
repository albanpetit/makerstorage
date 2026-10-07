# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # Throttle reset emails per IP so the form can't be used to spam inboxes.
  rate_limit to: 5, within: 15.minutes, only: :create, store: AUTH_RATE_LIMIT_STORE,
             with: -> { redirect_to new_user_password_path, alert: "Too many reset requests. Please wait a few minutes and try again." }
  # GET /forgot-password
  def new
    render inertia: "auth/forgot-password", props: {}
  end

  # POST /forgot-password
  # Same response whether or not the email has an account, so the form can't
  # be used to find out who's registered. (Devise's global `paranoid` mode would
  # do this too, but also hides the "account locked" sign-in message.)
  def create
    if resource_params[:email].blank?
      redirect_to new_user_password_path, alert: "Enter your email address."
      return
    end

    self.resource = resource_class.send_reset_password_instructions(resource_params)
    yield resource if block_given?

    redirect_to new_user_session_path, notice: I18n.t("devise.passwords.send_paranoid_instructions")
  end

  # GET /reset-password
  def edit
    reset_password_token = params[:reset_password_token]
    render inertia: "auth/reset-password", props: {
      reset_password_token: reset_password_token
    }
  end

  # PUT /reset-password
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    yield resource if block_given?

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)
      if Devise.sign_in_after_reset_password
        flash[:notice] = I18n.t("devise.passwords.updated")
        sign_in(resource_name, resource)
        redirect_to after_sign_in_path_for(resource)
      else
        flash[:notice] = I18n.t("devise.passwords.updated_not_active")
        redirect_to new_user_session_path
      end
    else
      flash[:alert] = resource.errors.full_messages.first
      redirect_to edit_user_password_path(reset_password_token: resource_params[:reset_password_token])
    end
  end

  protected

  def resource_params
    params.require(:user).permit(:email, :password, :password_confirmation, :reset_password_token)
  end
end

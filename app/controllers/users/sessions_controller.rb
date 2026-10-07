# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # Per-IP throttle against password spraying across many accounts; Devise's
  # :lockable separately locks a single account after repeated failures. Kept
  # generous: a makerspace class signs in all at once from one shared public IP.
  RATE_LIMIT = 60
  rate_limit to: RATE_LIMIT, within: 5.minutes, only: :create, store: AUTH_RATE_LIMIT_STORE,
             with: -> { redirect_to new_user_session_path, alert: "Too many sign-in attempts. Please wait a few minutes and try again." }
  # before_action :configure_sign_in_params, only: [:create]

  # GET /login
  def new
    render inertia: "auth/login", props: {}
  end

  # POST /login
  def create
    self.resource = warden.authenticate(auth_options)

    if resource
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      redirect_to after_sign_in_path_for(resource)
    else
      # Only a lockout gets its own message (a locked account has already seen
      # many attempts); everything else stays generic so it doesn't reveal
      # whether the email has an account.
      failure = warden.message == :locked ? :locked : :invalid
      flash[:alert] = I18n.t("devise.failure.#{failure}", authentication_keys: "Email")
      redirect_to new_user_session_path
    end
  end

  # DELETE /logout
  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    set_flash_message! :notice, :signed_out if signed_out
    yield if block_given?
    redirect_to new_user_session_path
  end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end

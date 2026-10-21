# frozen_string_literal: true

# Email confirmation (Devise :confirmable). The link from the confirmation mail
# lands on #show; a signed-in user asks for a fresh mail from their profile via
# #create. Plain redirects with a flash — there's no confirmation page of its own.
class Users::ConfirmationsController < Devise::ConfirmationsController
  # Each resend sends a mail, so throttle it like the password-reset form.
  RATE_LIMIT = 10
  rate_limit to: RATE_LIMIT, within: 15.minutes, only: :create, store: AUTH_RATE_LIMIT_STORE,
             with: -> { redirect_to profile_path, alert: t("flash.users_confirmations.too_many_confirmation_emails_requested_please") }

  # Devise skips authenticate_user! inside its own controllers unless forced.
  prepend_before_action -> { authenticate_user!(force: true) }, only: :create

  # GET /confirm-email?confirmation_token=…
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      notice = t("flash.users_confirmations.your_email_address_is_confirmed", email: resource.email)
      redirect_to(user_signed_in? ? profile_path : new_user_session_path, notice: notice)
    else
      alert = t("flash.users_confirmations.that_confirmation_link_is_invalid_or")
      redirect_to(user_signed_in? ? profile_path : new_user_session_path, alert: alert)
    end
  end

  # POST /confirm-email — resend to the signed-in user (to the new address when
  # an email change is waiting for confirmation).
  def create
    if current_user.confirmed? && !current_user.pending_reconfirmation?
      redirect_to profile_path, notice: t("flash.users_confirmations.your_email_address_is_already_confirmed")
      return
    end

    current_user.send_confirmation_instructions
    address = current_user.pending_reconfirmation? ? current_user.unconfirmed_email : current_user.email
    redirect_to profile_path, notice: t("flash.users_confirmations.we_sent_a_confirmation_link_to", address: address)
  end
end

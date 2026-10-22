# frozen_string_literal: true

# Lets the signed-in user answer an invitation to join an organization. Only
# their own pending invitations are reachable, and no current organization is
# required: someone whose every membership is pending lands on their profile,
# which is where invitations are listed.
class InvitationsController < ApplicationController
  include Auth

  before_action :require_confirmed_email
  before_action :set_invitation

  def accept
    @invitation.accept_invitation!
    session[:current_organization_id] = @invitation.organization_id
    redirect_to root_path, notice: t("flash.invitations.you_joined", organization_name: @invitation.organization.name)
  end

  def decline
    @invitation.destroy!
    redirect_to profile_path, notice: t("flash.invitations.invitation_to_declined", organization_name: @invitation.organization.name)
  end

  private

  # An invitation is addressed to an email: until the user proves they own it,
  # they might have signed up with someone else's address to intercept it.
  def require_confirmed_email
    return if current_user.can_answer_invitations?

    redirect_to profile_path, alert: t("flash.invitations.confirm_your_email_address_to_answer")
  end

  def set_invitation
    @invitation = current_user.pending_invitations.includes(:organization).find(params[:id])
  end
end

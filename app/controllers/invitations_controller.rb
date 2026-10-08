# frozen_string_literal: true

# Lets the signed-in user answer an invitation to join an organization. Only
# their own pending invitations are reachable, and no current organization is
# required: someone whose every membership is pending lands on their profile,
# which is where invitations are listed.
class InvitationsController < ApplicationController
  include Auth

  before_action :set_invitation

  def accept
    @invitation.accept_invitation!
    session[:current_organization_id] = @invitation.organization_id
    redirect_to root_path, notice: "You joined #{@invitation.organization.name}."
  end

  def decline
    @invitation.destroy!
    redirect_to profile_path, notice: "Invitation to #{@invitation.organization.name} declined."
  end

  private

  def set_invitation
    @invitation = current_user.pending_invitations.includes(:organization).find(params[:id])
  end
end

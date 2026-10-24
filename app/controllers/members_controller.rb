# frozen_string_literal: true

class MembersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_admin, only: %i[create update destroy]
  before_action :set_membership, only: %i[update destroy]
  before_action :verify_owner_role_authority, only: %i[create update]
  before_action :verify_owner_removal_authority, only: :destroy

  def index
    memberships = current_organization.organization_memberships.includes(:user).order(:created_at)

    render inertia: "members/index", props: {
      members: memberships.map { |membership| serialize_membership(membership) }
    }
  end

  def create
    email = params.dig(:member, :email).to_s.strip.downcase
    role = params.dig(:member, :role)
    user = User.find_by(email: email)

    unless OrganizationMembership::ROLES.include?(role)
      redirect_back_or_to members_path, alert: t("flash.members.choose_a_valid_role"), inertia: { errors: { "member.role" => [ "is not included in the list" ] } }
      return
    end

    # Answer exactly as for a sent invitation: anyone can sign up and own an
    # organization, so a distinct "no account" reply would let them probe which
    # emails are registered (the password-reset form hides this too).
    if user.nil?
      redirect_to members_path, notice: invitation_notice(email)
      return
    end

    if (existing = current_organization.organization_memberships.find_by(user: user))
      if existing.invitation_expired?
        # Renew rather than refuse: the old invitation is no longer offered.
        existing.update!(role: role, invited_by: current_user, invitation_sent_at: Time.current)
        redirect_to members_path, notice: invitation_notice(user.email)
        return
      end

      key = existing.pending_invitation? ? "already_invited" : "already_member"
      redirect_to members_path, alert: t("flash.members.#{key}", email: user.email)
      return
    end

    # An invitation, not a membership yet: it grants nothing until the invitee
    # accepts it from their profile, so nobody is enrolled without consent.
    membership = current_organization.organization_memberships.build(
      user: user, role: role, invited_by: current_user, invitation_sent_at: Time.current
    )

    if membership.save
      redirect_to members_path, notice: invitation_notice(user.email)
    else
      redirect_back_or_to members_path, alert: t("flash.members.failed_to_add_member"), inertia: { errors: inertia_errors(membership, as: :member) }
    end
  end

  def update
    if @membership.update(member_params)
      redirect_to members_path, notice: t("flash.members.role_updated_successfully")
    else
      redirect_to members_path, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    if @membership.destroy
      redirect_to members_path, notice: t("flash.members.member_removed_from_the_organization")
    else
      redirect_to members_path, alert: @membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_membership
    @membership = current_organization.organization_memberships.find(params[:id])
  end

  # Only an owner may grant the owner role or change an existing owner's role.
  # Admins are otherwise allowed to manage members, but must not be able to
  # escalate themselves (or anyone) to owner, or demote an owner.
  def verify_owner_role_authority
    requested_role = params.dig(:member, :role)
    crosses_owner =
      if @membership
        (requested_role == "owner") != @membership.owner?
      else
        requested_role == "owner"
      end

    return unless crosses_owner
    return if current_user.owner_of?(current_organization)

    redirect_to members_path, alert: t("flash.members.only_an_owner_can_assign_or")
  end

  # Removing an owner is at least as sensitive as demoting one, so it needs the
  # same authority: an admin may manage other members but must not be able to
  # kick out an owner. The last-owner guard on the membership still applies on
  # top of this (an owner can't remove the final owner either).
  def verify_owner_removal_authority
    return unless @membership.owner?
    return if current_user.owner_of?(current_organization)

    redirect_to members_path, alert: t("flash.members.only_an_owner_can_remove_another")
  end

  def invitation_notice(email)
    t("flash.members.invitation_sent", email: email)
  end

  def member_params
    params.require(:member).permit(:role)
  end

  def serialize_membership(membership)
    user = membership.user

    {
      id: membership.id,
      name: "#{user.firstname} #{user.lastname}".strip.presence || user.email,
      email: user.email,
      role: membership.role,
      active: membership.active,
      pending: membership.pending_invitation?,
      invitation_expired: membership.invitation_expired?,
      is_you: user.id == current_user.id,
      joined_at: membership.created_at.iso8601
    }
  end
end

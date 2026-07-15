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

    if user.nil?
      redirect_to members_path, alert: "No account found with that email. They need to create a Makerstorage account first."
      return
    end

    if current_organization.organization_memberships.exists?(user: user)
      redirect_to members_path, alert: "#{user.email} is already a member of this organization."
      return
    end

    membership = current_organization.organization_memberships.build(
      user: user, role: role, invited_by: current_user,
      invitation_sent_at: Time.current, invitation_accepted_at: Time.current
    )

    if membership.save
      redirect_to members_path, notice: "#{user.email} added to the organization."
    else
      redirect_back_or_to members_path, alert: "Failed to add member.", inertia: { errors: inertia_errors(membership, as: :member) }
    end
  end

  def update
    if @membership.update(member_params)
      redirect_to members_path, notice: "Role updated successfully."
    else
      redirect_to members_path, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    if @membership.destroy
      redirect_to members_path, notice: "Member removed from the organization."
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

    redirect_to members_path, alert: "Only an owner can assign or change the owner role."
  end

  # Removing an owner is at least as sensitive as demoting one, so it needs the
  # same authority: an admin may manage other members but must not be able to
  # kick out an owner. The last-owner guard on the membership still applies on
  # top of this (an owner can't remove the final owner either).
  def verify_owner_removal_authority
    return unless @membership.owner?
    return if current_user.owner_of?(current_organization)

    redirect_to members_path, alert: "Only an owner can remove another owner."
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
      is_you: user.id == current_user.id,
      joined_at: membership.created_at.iso8601
    }
  end
end

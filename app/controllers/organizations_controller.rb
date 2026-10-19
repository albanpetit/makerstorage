# frozen_string_literal: true

class OrganizationsController < ApplicationController
  include Auth

  def create
    organization = Organization.new(organization_params)

    ActiveRecord::Base.transaction do
      organization.save!
      organization.organization_memberships.create!(user: current_user, role: "owner")
    end

    session[:current_organization_id] = organization.id
    redirect_to root_path, notice: "Organization \"#{organization.name}\" created."
  rescue ActiveRecord::RecordInvalid
    redirect_back fallback_location: root_path,
                  inertia: { errors: inertia_errors(organization, as: :organization) },
                  alert: "Failed to create organization."
  end

  def switch
    organization = current_user.organizations.find_by(id: params[:id])

    if organization
      session[:current_organization_id] = organization.id
      redirect_back fallback_location: root_path, notice: "Switched to #{organization.name}"
    else
      redirect_back fallback_location: root_path, alert: "Organization not found"
    end
  end

  def destroy
    organization = current_user.organizations.find_by(id: params[:id])

    return redirect_back(fallback_location: root_path, alert: "Organization not found") unless organization

    unless current_user.owner_of?(organization)
      return redirect_back(fallback_location: root_path, alert: "You must be an owner to delete an organization.")
    end

    if organization.personal?
      return redirect_back(fallback_location: root_path, alert: "You can't delete a personal organization.")
    end

    if current_user.organizations.count <= 1
      return redirect_back(fallback_location: root_path, alert: "You can't delete your only organization.")
    end

    next_org = current_user.organizations.where.not(id: organization.id).first
    unless organization.destroy
      reason = organization.errors.full_messages.to_sentence.presence || "Some of its data could not be removed."
      return redirect_back(fallback_location: root_path, alert: "Could not delete \"#{organization.name}\". #{reason}")
    end
    session[:current_organization_id] = next_org&.id

    redirect_to root_path, notice: "Organization \"#{organization.name}\" was deleted."
  end

  # Deletes all of the organization's inventory data but keeps the
  # organization, its settings and its members. Owner-only, and confirmed by
  # typing the organization's name (checked here too, not only in the UI).
  def reset
    organization = owned_organization(params[:id])
    return unless organization
    return unless confirmed_by_name?(organization)

    count = organization.reset_data!
    redirect_to settings_path, notice: "\"#{organization.name}\" was reset (#{count} #{'part'.pluralize(count)} removed)."
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_back fallback_location: settings_path, alert: "Could not reset \"#{organization.name}\". Some of its data could not be removed."
  end

  # Moves everything in this organization into another one the user also owns,
  # then deletes this one (see OrganizationMerge).
  def merge
    source = owned_organization(params[:id])
    return unless source

    target = current_user.organizations.find_by(id: params[:target_id])
    unless target && current_user.owner_of?(target)
      return redirect_back(fallback_location: settings_path, alert: "Choose an organization you own to merge into.")
    end
    return unless confirmed_by_name?(source)

    result = OrganizationMerge.new(source: source, target: target).merge!
    session[:current_organization_id] = target.id
    redirect_to settings_path, notice: merge_notice(source, target, result)
  rescue OrganizationMerge::Error => e
    redirect_back fallback_location: settings_path, alert: "Could not merge \"#{source.name}\". #{e.message}"
  end

  private

  def owned_organization(id)
    organization = current_user.organizations.find_by(id: id)

    if organization.nil?
      redirect_back fallback_location: root_path, alert: "Organization not found"
    elsif !current_user.owner_of?(organization)
      redirect_back fallback_location: root_path, alert: "You must be an owner of \"#{organization.name}\" to do this."
    else
      return organization
    end
    nil
  end

  def confirmed_by_name?(organization)
    return true if params[:confirmation].to_s.strip == organization.name.strip

    redirect_back fallback_location: settings_path, alert: "Type the organization's name to confirm."
    false
  end

  def merge_notice(source, target, result)
    notice = "\"#{source.name}\" was merged into \"#{target.name}\": " \
             "#{result.parts_moved} #{'part'.pluralize(result.parts_moved)} moved, " \
             "#{result.parts_merged} merged with an existing part."
    details = []
    details << "#{result.codes_renamed} zone #{'code'.pluralize(result.codes_renamed)} renamed" if result.codes_renamed.positive?
    details << "#{result.ipns_reassigned} #{'IPN'.pluralize(result.ipns_reassigned)} reassigned" if result.ipns_reassigned.positive?
    blank = result.ipns_cleared - result.ipns_reassigned
    details << "#{blank} #{'part'.pluralize(blank)} left without an IPN (already taken)" if blank.positive?
    details << "#{result.members_added} #{'member'.pluralize(result.members_added)} added" if result.members_added.positive?
    details.any? ? "#{notice} #{details.join(', ').upcase_first}." : notice
  end

  def organization_params
    params.require(:organization).permit(:name)
  end
end

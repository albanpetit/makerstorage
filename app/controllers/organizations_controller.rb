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
    redirect_to root_path, notice: t("flash.organizations.organization_created", organization_name: organization.name)
  rescue ActiveRecord::RecordInvalid
    redirect_back fallback_location: root_path,
                  inertia: { errors: inertia_errors(organization, as: :organization) },
                  alert: t("flash.organizations.failed_to_create_organization")
  end

  def switch
    organization = current_user.organizations.find_by(id: params[:id])

    if organization
      session[:current_organization_id] = organization.id
      redirect_back fallback_location: root_path, notice: t("flash.organizations.switched_to", organization_name: organization.name)
    else
      redirect_back fallback_location: root_path, alert: t("flash.organizations.organization_not_found")
    end
  end

  def destroy
    organization = current_user.organizations.find_by(id: params[:id])

    return redirect_back(fallback_location: root_path, alert: t("flash.organizations.organization_not_found")) unless organization

    unless current_user.owner_of?(organization)
      return redirect_back(fallback_location: root_path, alert: t("flash.organizations.you_must_be_an_owner_to"))
    end

    if organization.personal?
      return redirect_back(fallback_location: root_path, alert: t("flash.organizations.you_can_t_delete_a_personal"))
    end

    if current_user.organizations.count <= 1
      return redirect_back(fallback_location: root_path, alert: t("flash.organizations.you_can_t_delete_your_only"))
    end

    next_org = current_user.organizations.where.not(id: organization.id).first
    unless organization.destroy
      reason = organization.errors.full_messages.to_sentence.presence || t("flash.organizations.some_of_its_data_could_not")
      return redirect_back(fallback_location: root_path, alert: t("flash.organizations.could_not_delete", organization_name: organization.name, reason: reason))
    end
    session[:current_organization_id] = next_org&.id

    redirect_to root_path, notice: t("flash.organizations.organization_was_deleted", organization_name: organization.name)
  end

  # Deletes all of the organization's inventory data but keeps the
  # organization, its settings and its members. Owner-only, and confirmed by
  # typing the organization's name (checked here too, not only in the UI).
  def reset
    organization = owned_organization(params[:id])
    return unless organization
    return unless confirmed_by_name?(organization)

    count = organization.reset_data!
    redirect_to settings_path, notice: t("flash.organizations.reset_done", name: organization.name, count: count)
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_back fallback_location: settings_path, alert: t("flash.organizations.could_not_reset_some_of_its", organization_name: organization.name)
  end

  # Moves everything in this organization into another one the user also owns,
  # then deletes this one (see OrganizationMerge).
  def merge
    source = owned_organization(params[:id])
    return unless source

    target = current_user.organizations.find_by(id: params[:target_id])
    unless target && current_user.owner_of?(target)
      return redirect_back(fallback_location: settings_path, alert: t("flash.organizations.choose_an_organization_you_own_to"))
    end
    return unless confirmed_by_name?(source)

    result = OrganizationMerge.new(source: source, target: target).merge!
    session[:current_organization_id] = target.id
    redirect_to settings_path, notice: merge_notice(source, target, result)
  rescue OrganizationMerge::Error => e
    redirect_back fallback_location: settings_path, alert: t("flash.organizations.could_not_merge", source_name: source.name, message: e.message)
  end

  private

  def owned_organization(id)
    organization = current_user.organizations.find_by(id: id)

    if organization.nil?
      redirect_back fallback_location: root_path, alert: t("flash.organizations.organization_not_found")
    elsif !current_user.owner_of?(organization)
      redirect_back fallback_location: root_path, alert: t("flash.organizations.you_must_be_an_owner_of", organization_name: organization.name)
    else
      return organization
    end
    nil
  end

  def confirmed_by_name?(organization)
    return true if params[:confirmation].to_s.strip == organization.name.strip

    redirect_back fallback_location: settings_path, alert: t("flash.organizations.type_the_organization_s_name_to")
    false
  end

  def merge_notice(source, target, result)
    notice = t("flash.organizations.merged", source: source.name, target: target.name,
               moved: t("flash.organizations.merged_moved", count: result.parts_moved),
               merged: t("flash.organizations.merged_merged", count: result.parts_merged))
    details = []
    details << t("flash.organizations.merged_codes", count: result.codes_renamed) if result.codes_renamed.positive?
    details << t("flash.organizations.merged_ipns", count: result.ipns_reassigned) if result.ipns_reassigned.positive?
    blank = result.ipns_cleared - result.ipns_reassigned
    details << t("flash.organizations.merged_blank", count: blank) if blank.positive?
    details << t("flash.organizations.merged_members", count: result.members_added) if result.members_added.positive?
    details.any? ? "#{notice} #{details.join(', ').upcase_first}." : notice
  end

  def organization_params
    params.require(:organization).permit(:name)
  end
end

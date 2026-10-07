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

  private

  def organization_params
    params.require(:organization).permit(:name)
  end
end

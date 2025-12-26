# frozen_string_literal: true

class OrganizationsController < ApplicationController
  include Auth

  def switch
    organization = current_user.organizations.find_by(id: params[:id])

    if organization
      session[:current_organization_id] = organization.id
      redirect_back fallback_location: root_path, notice: "Switched to #{organization.name}"
    else
      redirect_back fallback_location: root_path, alert: "Organization not found"
    end
  end
end

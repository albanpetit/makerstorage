class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  inertia_share flash: -> { flash.to_hash }

  inertia_share auth: -> {
    if user_signed_in?
      {
        user: {
          email: current_user.email,
          firstname: current_user.firstname,
          lastname: current_user.lastname
        },
        current_organization: current_organization ? serialize_organization(current_organization) : nil,
        organizations: current_user.organizations.order(:name).map { |org| serialize_organization(org) }
      }
    end
  }

  helper_method :current_organization

  def current_organization
    return nil unless user_signed_in?

    @current_organization ||= begin
      org_id = session[:current_organization_id]
      if org_id && current_user.organizations.exists?(id: org_id)
        current_user.organizations.find(org_id)
      else
        org = current_user.organizations.first
        session[:current_organization_id] = org&.id
        org
      end
    end
  end

  private

  def serialize_organization(org)
    {
      id: org.id,
      name: org.name
    }
  end
end

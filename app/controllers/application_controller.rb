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
        organizations: current_user.organizations.order(:name).map { |org| serialize_organization(org) },
        alerts_count: current_organization&.low_stock_parts_count || 0,
        is_organization_admin: current_organization ? current_user.admin_of?(current_organization) : false,
        is_organization_writer: current_organization ? current_user.writer_of?(current_organization) : false,
        organization_role: current_organization ? current_user.role_in(current_organization) : nil
      }
    end
  }

  helper_method :current_organization

  def current_organization
    return nil unless user_signed_in?

    @current_organization ||= begin
      org_id = session[:current_organization_id]
      if org_id && current_user.member_of_organization?(org_id)
        current_user.organizations.find(org_id)
      else
        org = current_user.organizations.first
        session[:current_organization_id] = org&.id
        org
      end
    end
  end

  private

  # Namespace an ActiveModel's validation errors so their keys match the nested
  # Inertia form data. React forms use `useForm({ part: { name } })`, so Inertia
  # types (and reads) errors as dotted paths like `part.name`. Rails' default
  # `errors.to_hash` emits flat keys (`name`), which never match — so inline
  # field errors silently fail to render unless we prefix them here.
  def inertia_errors(model, as:)
    model.errors.to_hash.transform_keys { |attribute| "#{as}.#{attribute}" }
  end

  def serialize_organization(org)
    {
      id: org.id,
      name: org.name,
      member_count: org.organization_memberships.active.count,
      logo_url: org.logo.attached? ? rails_blob_path(org.logo, only_path: true) : nil
    }
  end

  # Verify user has access to current organization
  def verify_organization_access
    unless current_organization && current_user.member_of_organization?(current_organization.id)
      redirect_to root_path, alert: "You don't have access to this organization"
    end
  end

  # Verify user may write in the current organization (blocks viewers)
  def verify_organization_writer
    unless current_organization && current_user.writer_of?(current_organization)
      redirect_back_or_to root_path, alert: "Your role is read-only for this organization."
    end
  end

  # Verify user is admin/owner of current organization (for sensitive operations)
  def verify_organization_admin
    unless current_organization && current_user.admin_of?(current_organization)
      redirect_to root_path, alert: "You don't have admin access to this organization"
    end
  end

  # Verify user is owner of current organization (for critical operations)
  def verify_organization_owner
    unless current_organization && current_user.owner_of?(current_organization)
      redirect_to root_path, alert: "You must be an owner to perform this action"
    end
  end
end

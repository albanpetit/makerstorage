class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Cache backing the per-IP auth rate limits (see Users::*Controller). The app
  # cache in production; test swaps in a real store via config.x.
  AUTH_RATE_LIMIT_STORE = Rails.application.config.x.rate_limit_store || Rails.cache

  inertia_share flash: -> { flash.to_hash }
  # The React UI translates itself from this (app/frontend/lib/i18n.ts).
  inertia_share locale: -> { I18n.locale.to_s }

  inertia_share auth: -> {
    if user_signed_in?
      {
        user: {
          email: current_user.email,
          firstname: current_user.firstname,
          lastname: current_user.lastname
        },
        current_organization: current_organization ? serialize_organization(current_organization).merge(member_count: current_organization.organization_memberships.granting_access.count) : nil,
        # Shared by every page: logos preloaded, and no per-organization member
        # count (only the current one shows it), so it costs the same whatever
        # the number of organizations.
        organizations: current_user.organizations.with_attached_logo.order(:name).map { |org| serialize_organization(org) },
        alerts_count: current_organization&.low_stock_parts_count || 0,
        overdue_loans_count: current_organization ? current_organization.loans.overdue_on(current_organization.local_date).count : 0,
        is_organization_admin: current_organization ? current_user.admin_of?(current_organization) : false,
        is_organization_writer: current_organization ? current_user.writer_of?(current_organization) : false,
        organization_role: current_organization ? current_user.role_in(current_organization) : nil,
        pending_invitations_count: current_user.can_answer_invitations? ? current_user.pending_invitations.count : 0
      }
    end
  }

  helper_method :current_organization

  # "Today", default order dates, generated references (PO-YYYYMMDD…) and every
  # serialized timestamp follow the organization's configured time zone rather
  # than the server's (UTC).
  around_action :use_organization_time_zone

  # UI language: the user's choice (profile), else the best match for the
  # browser's Accept-Language, else English. Flash messages, validation errors
  # and the React UI all follow it.
  around_action :switch_locale

  # Who the activity log credits for changes made during this request (Auditable).
  before_action :set_current_user

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

  def set_current_user
    Current.user = current_user if user_signed_in?
  end

  def switch_locale(&action)
    I18n.with_locale(user_signed_in? && current_user.locale.presence || browser_locale, &action)
  end

  # First Accept-Language entry (by q-value) whose language we have, e.g.
  # "fr-CA,fr;q=0.9,en;q=0.8" → :fr. Region subtags are ignored.
  def browser_locale
    available = I18n.available_locales.map(&:to_s)
    request.headers["Accept-Language"].to_s.split(",").filter_map { |entry|
      tag, *params = entry.strip.split(";")
      quality = params.find { |param| param.strip.start_with?("q=") }&.strip&.delete_prefix("q=")&.to_f || 1.0
      language = tag.to_s.strip.downcase.split("-").first
      [ language, quality ] if available.include?(language) && quality.positive?
    }.max_by.with_index { |(_, quality), index| [ quality, -index ] }&.first || I18n.default_locale
  end

  def use_organization_time_zone(&action)
    Time.use_zone(current_organization&.timezone || Time.zone_default, &action)
  end

  # Namespace an ActiveModel's validation errors so their keys match the nested
  # Inertia form data. React forms use `useForm({ part: { name } })`, so Inertia
  # types (and reads) errors as dotted paths like `part.name`. Rails' default
  # `errors.to_hash` emits flat keys (`name`), which never match — so inline
  # field errors silently fail to render unless we prefix them here.
  def inertia_errors(model, as:)
    model.errors.to_hash.transform_keys { |attribute| "#{as}.#{attribute}" }
  end

  # Link to an uploaded file, served to members only (StoredFilesController).
  def stored_file_path_for(attachment)
    stored_file_path(attachment.blob.signed_id, attachment.filename.to_s)
  end

  def serialize_organization(org)
    {
      id: org.id,
      name: org.name,
      logo_url: org.logo.attached? ? stored_file_path_for(org.logo) : nil
    }
  end

  # The email digest links to alerts and loans with their organization, so a
  # member of several lands on what they were mailed about. Ignored for an
  # organization the user doesn't belong to.
  def switch_to_linked_organization
    organization = current_user.organizations.find_by(id: params[:organization_id]) if params[:organization_id].present?
    return unless organization

    session[:current_organization_id] = organization.id
    @current_organization = organization
  end

  # Verify user has access to current organization
  def verify_organization_access
    # No active membership anywhere (e.g. deactivated everywhere): the root page
    # needs an organization too, so sending them there would loop forever. The
    # profile page doesn't, and its sidebar offers "Create organization".
    if current_organization.nil?
      redirect_to profile_path, alert: t("flash.application.you_re_not_an_active_member")
    elsif !current_user.member_of_organization?(current_organization.id)
      redirect_to root_path, alert: t("flash.application.you_don_t_have_access_to")
    end
  end

  # Verify user may write in the current organization (blocks viewers)
  def verify_organization_writer
    return if current_organization && current_user.writer_of?(current_organization)

    message = t("flash.application.your_role_is_read_only_for")
    if request.format.json?
      render json: { error: message }, status: :forbidden
    else
      redirect_back_or_to root_path, alert: message
    end
  end

  # Verify user is admin/owner of current organization (for sensitive operations)
  def verify_organization_admin
    unless current_organization && current_user.admin_of?(current_organization)
      redirect_to root_path, alert: t("flash.application.you_don_t_have_admin_access")
    end
  end

  # Verify user is owner of current organization (for critical operations)
  def verify_organization_owner
    unless current_organization && current_user.owner_of?(current_organization)
      redirect_to root_path, alert: t("flash.application.you_must_be_an_owner_to")
    end
  end
end

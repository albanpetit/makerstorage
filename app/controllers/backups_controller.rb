# frozen_string_literal: true

# Organization backups (see OrganizationBackup): admins download the current
# organization as a ZIP archive, and any signed-in user restores an archive
# into a new organization they own.
class BackupsController < ApplicationController
  include Auth

  before_action :verify_organization_access, only: :export
  before_action :verify_organization_admin, only: :export
  # A restore is heavy (the whole archive is read and parsed in the request) and
  # open to any account, so it's limited per user and needs a confirmed address
  # when addresses are verified.
  before_action :verify_confirmed_email, only: :import
  rate_limit to: IMPORT_RATE_LIMIT = 5, within: 1.hour, only: :import, by: -> { current_user.id }, store: AUTH_RATE_LIMIT_STORE,
             with: -> { redirect_back_or_to settings_path, alert: "Too many restores. Please try again later." }

  def export
    send_data OrganizationBackup::Exporter.new(current_organization).to_zip,
              filename: OrganizationBackup.filename_for(current_organization),
              type: "application/zip",
              disposition: "attachment"
  end

  def import
    file = params[:file]
    return redirect_back_or_to(settings_path, alert: "Please choose a backup file to restore.") unless file.respond_to?(:path)

    result = OrganizationBackup::Importer.new(file.path, user: current_user, name: params[:name]).import!
    session[:current_organization_id] = result.organization.id

    notice = "Restored \"#{result.organization.name}\" (#{result.records_count} #{'record'.pluralize(result.records_count)}, " \
             "#{result.files_count} #{'file'.pluralize(result.files_count)})."
    if result.skipped_files.any?
      notice += " Skipped #{result.skipped_files.size} #{'file'.pluralize(result.skipped_files.size)} that couldn't be restored."
    end
    redirect_to settings_path, notice: notice
  rescue OrganizationBackup::Error => e
    redirect_back_or_to settings_path, alert: "Could not restore the backup. #{e.message}"
  end

  private

  def verify_confirmed_email
    return if !User.email_verification? || current_user.confirmed?

    redirect_back_or_to settings_path, alert: "Confirm your email address before restoring a backup."
  end
end

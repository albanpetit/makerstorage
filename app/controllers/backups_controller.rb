# frozen_string_literal: true

# Organization backups (see OrganizationBackup): admins download the current
# organization as a ZIP archive, and any signed-in user restores an archive
# into a new organization they own.
class BackupsController < ApplicationController
  include Auth

  before_action :verify_organization_access, only: :export
  before_action :verify_organization_admin, only: :export

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
end

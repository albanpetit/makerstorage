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

  # The archive is built in a temporary file and streamed from disk (the file
  # is deleted once the response is sent), so a large organization doesn't
  # have to fit in memory.
  def export
    path = Rails.root.join("tmp", "backups", "#{SecureRandom.uuid}.zip")
    FileUtils.mkdir_p(path.dirname)
    OrganizationBackup::Exporter.new(current_organization).write_to(path.to_s)

    response.headers["Content-Type"] = "application/zip"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment", filename: OrganizationBackup.filename_for(current_organization)
    )
    response.headers["Content-Length"] = File.size(path).to_s
    self.response_body = TemporaryFileBody.new(path.to_s)
  rescue StandardError
    FileUtils.rm_f(path) if path
    raise
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

  # A Rack body served from a file (by path, so the server can stream it) that
  # deletes the file once the response is done.
  class TemporaryFileBody
    CHUNK_SIZE = 64.kilobytes

    attr_reader :to_path

    def initialize(path)
      @to_path = path
    end

    def each
      File.open(to_path, "rb") do |file|
        while (chunk = file.read(CHUNK_SIZE))
          yield chunk
        end
      end
    end

    def close
      FileUtils.rm_f(to_path)
    end
  end

  def verify_confirmed_email
    return if !User.email_verification? || current_user.confirmed?

    redirect_back_or_to settings_path, alert: "Confirm your email address before restoring a backup."
  end
end

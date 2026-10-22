# frozen_string_literal: true

# Links a project to a GitHub repository its KiCad files come from, and fetches
# them again on demand (ProjectGithubSync).
class ProjectGithubController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_project

  LINK_COLUMNS = %w[github_repository github_ref github_path].freeze

  # Sets (or changes) the link, then fetches the files.
  def update
    attributes = ProjectGithubController.link_attributes(params)
    return redirect_to(project_path(@project), alert: t("flash.project_github.enter_repository")) unless attributes

    @project.assign_attributes(attributes)
    # Another repository, ref or folder: fetch again even at the same commit.
    @project.github_synced_sha = nil if (@project.changed & LINK_COLUMNS).any?
    unless @project.save
      return redirect_to(project_path(@project), alert: @project.errors.full_messages.to_sentence)
    end

    redirect_to project_path(@project), ProjectGithubController.sync_flash(@project)
  end

  def sync
    redirect_to project_path(@project), ProjectGithubController.sync_flash(@project, force: ActiveModel::Type::Boolean.new.cast(params[:force]))
  end

  def destroy
    @project.unlink_github!
    redirect_to project_path(@project), notice: t("flash.project_github.unlinked")
  end

  # { github_repository:, github_ref:, github_path: } from the form: the
  # repository field takes "owner/name" or a URL, whose branch and folder fill
  # the other fields when they're left blank. nil when no repository is given.
  def self.link_attributes(params)
    return nil if params[:repository].blank?

    parsed = GithubClient.parse(params[:repository]) || { repository: params[:repository].to_s.strip, ref: nil, path: nil }
    {
      github_repository: parsed[:repository],
      github_ref: params[:ref].to_s.strip.presence || parsed[:ref],
      github_path: params[:path].to_s.strip.presence || parsed[:path]
    }
  end

  # Runs a sync and turns its outcome into a flash (notice or alert).
  def self.sync_flash(project, force: false)
    result = ProjectGithubSync.call(project, force: force)
    short = result.sha.first(7)
    return { notice: I18n.t("flash.project_github.up_to_date", location: project.github_location, sha: short) } if result.status == :up_to_date

    notice = I18n.t("flash.project_github.fetched", count: result.file_count, location: project.github_location, sha: short)
    notice += " " +
      case result.bom
      when :replaced then I18n.t("flash.project_files.bom_updated", count: result.line_count)
      when :unchanged then I18n.t("flash.project_github.bom_unchanged")
      else I18n.t("flash.project_github.no_schematic")
      end
    { notice: notice }
  rescue ProjectGithubSync::Error => e
    { alert: e.message }
  rescue ActiveRecord::RecordInvalid => e
    { alert: e.record.errors.full_messages.to_sentence }
  end

  private

  def set_project
    @project = current_organization.projects.includes(:project_lines, kicad_files_attachments: :blob).find(params[:project_id])
  end
end

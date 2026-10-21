# frozen_string_literal: true

# A project's design files (KiCad files or a ZIP of the project folder):
# adding, removing, and refilling the BOM from the schematics among them.
class ProjectFilesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_project

  # Attaches the uploaded files. A project with no BOM yet gets one from the
  # schematics; otherwise refilling it is left to #import_bom, since it would
  # replace the reviewed lines.
  def create
    uploads = Array(params[:files]).select { |upload| upload.respond_to?(:original_filename) }
    return redirect_to(project_path(@project), alert: "Please choose files to add.") if uploads.empty?

    if (error = ProjectKicadFiles.upload_error(uploads, existing: @project.kicad_files.size))
      return redirect_to(project_path(@project), alert: error)
    end

    lines = []
    if @project.project_lines.empty?
      lines = ProjectKicadFiles.bom_lines(ProjectKicadFiles.upload_files(uploads))
    end

    ActiveRecord::Base.transaction do
      @project.kicad_files.attach(ProjectKicadFiles.attachables(uploads))
      @project.save!
      @project.replace_bom!(lines) if lines.any?
    end

    notice = "Added #{uploads.size} file#{'s' if uploads.size != 1}."
    notice += " Imported #{lines.size} BOM lines from the schematic." if lines.any?
    redirect_to project_path(@project), notice: notice
  rescue ProjectKicadFiles::Unreadable => e
    redirect_to project_path(@project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    file = @project.kicad_files.find(params[:id])
    file.purge
    redirect_to project_path(@project), notice: "#{file.filename} removed."
  end

  # Rebuilds the BOM from the attached schematics after a design change.
  def import_bom
    lines = ProjectKicadFiles.bom_lines_for(@project)
    if lines.empty?
      return redirect_to(project_path(@project), alert: "No schematic (.kicad_sch) with components among this project's files.")
    end

    @project.replace_bom!(lines)
    redirect_to project_path(@project), notice: "BOM updated from the schematic: #{lines.size} lines. Review the matches below."
  rescue ProjectKicadFiles::Unreadable => e
    redirect_to project_path(@project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_project
    @project = current_organization.projects.includes(:project_lines).find(params[:project_id])
  end
end

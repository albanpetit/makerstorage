# frozen_string_literal: true

class ProjectLinesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_line, except: :create

  # Adds a line by hand: an inventory part, or a free-text component that
  # isn't in stock yet (a designation or reference is then required).
  def create
    project = current_organization.projects.find(params[:project_id])
    line_params = params.require(:project_line).permit(:part_id, :raw_reference, :designation, :value, :footprint, :designators, :quantity)
    part = line_params[:part_id].presence && current_organization.parts.find_by(id: line_params[:part_id])

    line = project.project_lines.new(
      line_params.except(:part_id).to_h.transform_values { |value| value.to_s.strip.presence }.merge(
        part: part, match_type: part ? "manual" : "none"
      )
    )
    line.raw_reference ||= part && (part.mpn.presence || part.reference)
    line.designation ||= part&.name
    line.quantity ||= 1

    if line.designation.blank? && line.raw_reference.blank?
      line.errors.add(:part_id, "or a designation is required")
    elsif line.save
      return redirect_to(project_path(project), notice: "Line added.")
    end

    redirect_to project_path(project),
      alert: line.errors.full_messages.to_sentence,
      inertia: { errors: inertia_errors(line, as: :project_line) }
  end

  # The confirm-step edit: re-point a line at a different inventory part (or
  # clear the match), and/or change the required quantity. Choosing a part by
  # hand is recorded as a "manual" match; clearing it falls back to "none".
  def update
    line_params = params.require(:project_line)
    attributes = {}

    if line_params.key?(:part_id)
      part_id = params.dig(:project_line, :part_id).presence
      part = part_id && current_organization.parts.find_by(id: part_id)
      attributes[:part] = part
      attributes[:match_type] = part ? "manual" : "none"
    end

    if line_params.key?(:quantity)
      attributes[:quantity] = params.dig(:project_line, :quantity)
    end

    if @line.update(attributes)
      redirect_to project_path(@line.project), notice: "Line updated."
    else
      redirect_to project_path(@line.project),
        alert: @line.errors.full_messages.to_sentence,
        inertia: { errors: inertia_errors(@line, as: :project_line) }
    end
  end

  def destroy
    project = @line.project
    @line.destroy!
    redirect_to project_path(project), notice: "Line removed."
  end

  private

  def set_line
    @line = ProjectLine.joins(:project)
      .where(projects: { organization_id: current_organization.id })
      .find(params[:id])
  end
end

# frozen_string_literal: true

class ProjectLinesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_line

  # The confirm-step edit: re-point a line at a different inventory part (or
  # clear the match), and/or change the required quantity. Choosing a part by
  # hand is recorded as a "manual" match; clearing it falls back to "none".
  def update
    attributes = {}

    if params[:project_line].key?(:part_id)
      part_id = params.dig(:project_line, :part_id).presence
      part = part_id && current_organization.parts.find_by(id: part_id)
      attributes[:part] = part
      attributes[:match_type] = part ? "manual" : "none"
    end

    if params[:project_line].key?(:quantity)
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

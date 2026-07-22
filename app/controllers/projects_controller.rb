# frozen_string_literal: true

class ProjectsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create confirm create_purchase_orders build destroy]
  before_action :set_project, only: %i[show confirm create_purchase_orders build destroy]

  def index
    projects = current_organization.projects
      .includes(project_lines: { part: :part_storages })
      .recent

    render inertia: "projects/index", props: {
      projects: projects.map { |project| serialize_project_summary(project) }
    }
  end

  def show
    render inertia: "projects/show", props: {
      project: serialize_project(@project),
      # Lightweight pick-list for the review UI's re-match combobox.
      parts: current_organization.parts.alphabetical.map do |part|
        { id: part.id, reference: part.reference, name: part.name, mpn: part.mpn, sku: part.sku }
      end
    }
  end

  def create
    file = params[:file]
    return redirect_to(projects_path, alert: "Please choose a CSV file to import.") unless file

    name = params[:name].presence || File.basename(file.original_filename.to_s, ".*").presence || "Untitled project"

    begin
      lines = BomParser.parse(file.path)
    rescue CSV::MalformedCSVError
      return redirect_to(projects_path, alert: "Could not parse that file as CSV.")
    end

    if lines.empty?
      return redirect_to(projects_path, alert: "That file has no usable BOM rows.")
    end

    project = current_organization.projects.new(name: name, status: "draft")
    project.reference = Project.next_reference(current_organization)

    lines.each do |line|
      part, match_type = BomParser.match(current_organization, line)
      project.project_lines.build(
        part: part,
        match_type: match_type,
        raw_reference: line[:mpn].presence || line[:sku],
        designation: line[:designation],
        quantity: line[:quantity]
      )
    end

    if project.save
      redirect_to project_path(project), notice: "Imported #{project.project_lines.size} BOM lines. Review the matches below."
    else
      redirect_to projects_path, alert: project.errors.full_messages.to_sentence.presence || "Could not import that BOM."
    end
  end

  def confirm
    @project.update!(status: "confirmed", checked_at: Time.current)
    redirect_to project_path(@project), notice: "Matches confirmed."
  end

  # Turns each short, matched line into a purchase order, grouped by the part's
  # preferred supplier. Mirrors AlertsController#create_purchase_orders.
  def create_purchase_orders
    candidates = @project.short_lines.filter_map do |line|
      supplier_link = line.part.preferred_part_supplier
      next unless supplier_link

      {
        part: line.part,
        supplier: supplier_link.supplier,
        quantity: line.shortfall,
        unit_price: (supplier_link.unit_price || line.part.unit_price || 0).to_f
      }
    end

    if candidates.empty?
      redirect_to project_path(@project), alert: "No short line has a preferred supplier to order from."
      return
    end

    created = 0
    grouped = candidates.group_by { |c| c[:supplier] }

    grouped.each do |supplier, entries|
      total = entries.sum { |e| e[:quantity] * e[:unit_price] }

      order = current_organization.orders.create!(
        supplier: supplier,
        status: "pending",
        ordered_at: Date.current,
        reference: Order.next_reference(current_organization, supplier),
        total_amount: total
      )

      entries.each do |entry|
        OrderLine.create!(
          order: order, part: entry[:part],
          quantity: entry[:quantity], unit_price: entry[:unit_price]
        )
      end

      created += 1
    end

    references = grouped.values.flatten.size
    redirect_to project_path(@project),
      notice: "Created #{created} purchase order#{'s' if created != 1} for #{references} reference#{'s' if references != 1}."
  end

  # Consumes the required quantity of every matched line from stock, recording an
  # "out" movement per source location. Only allowed when the project is fully
  # buildable, so we never leave a kit half-deducted.
  def build
    unless @project.buildable?
      redirect_to project_path(@project), alert: "This project isn't buildable yet — resolve shortfalls and unmatched lines first."
      return
    end

    ActiveRecord::Base.transaction do
      @project.project_lines.each { |line| deduct_line_stock(line) }
    end

    redirect_to project_path(@project), notice: "Stock deducted for #{@project.project_lines.size} references."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: "Could not deduct stock: #{e.record.errors.full_messages.to_sentence}."
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def set_project
    @project = current_organization.projects
      .includes(project_lines: { part: [ :part_storages, { part_suppliers: :supplier } ] })
      .find(params[:id])
  end

  # Draws +line.quantity+ down across the part's positive-stock locations,
  # emitting an "out" StockMovement for each source touched.
  def deduct_line_stock(line)
    remaining = line.quantity

    line.part.part_storages.select { |ps| ps.quantity.positive? }.each do |storage|
      break if remaining <= 0

      take = [ storage.quantity, remaining ].min
      current_organization.stock_movements.create!(
        part: line.part, storage_location: storage.storage_location, user: current_user,
        movement_type: "out", quantity_delta: -take, reason: "Build #{@project.reference}"
      )
      remaining -= take
    end
  end

  def serialize_project_summary(project)
    {
      id: project.id,
      name: project.name,
      reference: project.reference,
      status: project.status,
      line_count: project.project_lines.size,
      buildable: project.buildable?,
      short_count: project.short_lines.size,
      unmatched_count: project.unmatched_lines.size,
      checked_at: project.checked_at&.iso8601,
      created_at: project.created_at.iso8601
    }
  end

  def serialize_project(project)
    {
      id: project.id,
      name: project.name,
      reference: project.reference,
      status: project.status,
      buildable: project.buildable?,
      short_count: project.short_lines.size,
      unmatched_count: project.unmatched_lines.size,
      checked_at: project.checked_at&.iso8601,
      lines: project.project_lines.map { |line| serialize_line(line) }
    }
  end

  def serialize_line(line)
    {
      id: line.id,
      raw_reference: line.raw_reference,
      designation: line.designation,
      quantity: line.quantity,
      match_type: line.match_type,
      in_stock: line.in_stock,
      shortfall: line.shortfall,
      available: line.available?,
      part: line.part && {
        id: line.part.id,
        reference: line.part.reference,
        name: line.part.name
      }
    }
  end
end

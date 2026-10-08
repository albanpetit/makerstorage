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

    project.save_with_generated_reference! { Project.next_reference(current_organization) }
    redirect_to project_path(project), notice: "Imported #{project.project_lines.size} BOM lines. Review the matches below."
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence.presence || "Could not import that BOM."
  end

  def confirm
    @project.update!(status: "confirmed", checked_at: Time.current)
    redirect_to project_path(@project), notice: "Matches confirmed."
  end

  # Orders each short part's missing quantity (summed across its BOM lines),
  # minus what's already on an open order, grouped by the part's preferred
  # supplier. Mirrors AlertsController#create_purchase_orders.
  def create_purchase_orders
    shortfalls = @project.shortfall_by_part
    incoming = Order.incoming_quantities(current_organization, shortfalls.keys.map(&:id))

    candidates = shortfalls.filter_map do |part, shortfall|
      supplier_link = part.preferred_part_supplier
      quantity = shortfall - incoming.fetch(part.id, 0)
      next unless supplier_link && quantity.positive?

      {
        part: part,
        supplier: supplier_link.supplier,
        quantity: quantity,
        unit_price: (supplier_link.unit_price || part.unit_price || 0).to_f
      }
    end

    if candidates.empty?
      redirect_to project_path(@project), alert: "Nothing left to order: short parts have no preferred supplier or are already on open purchase orders."
      return
    end

    created = 0
    grouped = candidates.group_by { |c| c[:supplier] }

    # All or nothing: a failure on one supplier mustn't leave the others' orders
    # behind, or a retry would duplicate them.
    ActiveRecord::Base.transaction do
      grouped.each do |supplier, entries|
        total = entries.sum { |e| e[:quantity] * e[:unit_price] }

        order = current_organization.orders.new(
          supplier: supplier, status: "pending", ordered_at: Date.current, total_amount: total
        )
        order.save_with_generated_reference! { Order.next_reference(current_organization, supplier) }

        entries.each do |entry|
          OrderLine.create!(
            order: order, part: entry[:part],
            quantity: entry[:quantity], unit_price: entry[:unit_price]
          )
        end

        created += 1
      end
    end

    references = grouped.values.flatten.size
    redirect_to project_path(@project),
      notice: "Created #{created} purchase order#{'s' if created != 1} for #{references} reference#{'s' if references != 1}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: "No purchase order was created: #{e.record.errors.full_messages.to_sentence}."
  end

  # Consumes the required quantity of every matched line from stock, recording an
  # "out" movement per source location. Only allowed when the project is fully
  # buildable, so we never leave a kit half-deducted.
  #
  # Building the same kit again is legitimate, but a double click or a replayed
  # request must not deduct it twice. The page posts the builds_count it showed;
  # the build only goes ahead if bumping that exact count succeeds — an atomic
  # compare-and-increment, so a second, stale submission matches no row.
  def build
    unless @project.buildable?
      redirect_to project_path(@project), alert: "This project isn't buildable yet — resolve shortfalls and unmatched lines first."
      return
    end

    required = @project.required_by_part
    built = ActiveRecord::Base.transaction do
      claimed = Project.where(id: @project.id, builds_count: params[:builds_count].to_s.presence&.to_i)
        .update_all([ "builds_count = builds_count + 1, last_built_at = ?, updated_at = ?", Time.current, Time.current ])
      raise ActiveRecord::Rollback if claimed.zero?

      required.each { |part, quantity| deduct_part_stock(part, quantity) }
      true
    end

    unless built
      redirect_to project_path(@project), alert: "This kit was already built from this page. Reload to build another one."
      return
    end

    redirect_to project_path(@project), notice: "Stock deducted for #{required.size} reference#{'s' if required.size != 1}."
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

  # Draws +quantity+ of +part+ down across its positive-stock locations,
  # emitting an "out" StockMovement for each source touched. Called once per
  # part, so the preloaded storage quantities are still current.
  def deduct_part_stock(part, quantity)
    remaining = quantity

    part.part_storages.select { |ps| ps.quantity.positive? }.each do |storage|
      break if remaining <= 0

      take = [ storage.quantity, remaining ].min
      current_organization.stock_movements.create!(
        part: part, storage_location: storage.storage_location, user: current_user,
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
    shortfalls = project.shortfall_by_part
    {
      id: project.id,
      name: project.name,
      reference: project.reference,
      status: project.status,
      buildable: project.buildable?,
      short_count: project.short_lines.size,
      unmatched_count: project.unmatched_lines.size,
      checked_at: project.checked_at&.iso8601,
      builds_count: project.builds_count,
      last_built_at: project.last_built_at&.iso8601,
      lines: project.project_lines.map { |line| serialize_line(line, shortfalls) }
    }
  end

  # Shortfall and availability come from the project-wide per-part totals, so a
  # part listed on two lines isn't shown as available on each when its stock
  # only covers one.
  def serialize_line(line, shortfalls)
    shortfall = line.part ? shortfalls.fetch(line.part, 0) : 0
    {
      id: line.id,
      raw_reference: line.raw_reference,
      designation: line.designation,
      quantity: line.quantity,
      match_type: line.match_type,
      in_stock: line.in_stock,
      shortfall: shortfall,
      available: line.part.present? && shortfall.zero?,
      part: line.part && {
        id: line.part.id,
        reference: line.part.reference,
        name: line.part.name
      }
    }
  end
end

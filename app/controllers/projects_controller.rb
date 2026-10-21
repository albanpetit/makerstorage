# frozen_string_literal: true

class ProjectsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update duplicate confirm reserve release create_purchase_orders build destroy]
  before_action :set_project, only: %i[show update duplicate confirm reserve release create_purchase_orders build destroy]

  # Most kits one build can deduct at once.
  MAX_BUILD_KITS = 1_000
  # Builds listed on the project page, newest first.
  BUILD_HISTORY_LIMIT = 50

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
    return create_empty unless file
    return redirect_to(projects_path, alert: BomParser.too_large_message) if BomParser.too_large?(file)

    name = params[:name].presence || File.basename(file.original_filename.to_s, ".*").presence || "Untitled project"

    begin
      lines = BomParser.parse(file.path)
    rescue CSV::MalformedCSVError
      return redirect_to(projects_path, alert: "Could not parse that file as CSV.")
    rescue Nokogiri::XML::SyntaxError, BomParser::Kicad::NotANetlist
      return redirect_to(projects_path, alert: "Could not read that file as a KiCad BOM (XML).")
    end

    if lines.empty?
      return redirect_to(projects_path, alert: "That file has no usable BOM rows.")
    end

    project = current_organization.projects.new(name: name, status: "draft")
    matcher = BomParser::Matcher.new(current_organization)

    lines.each do |line|
      part, match_type = matcher.match(line)
      project.project_lines.build(
        part: part,
        match_type: match_type,
        raw_reference: line[:mpn].presence || line[:sku],
        designation: line[:designation],
        value: line[:value],
        footprint: line[:footprint],
        designators: line[:designators],
        quantity: line[:quantity]
      )
    end

    project.save_with_generated_reference! { Project.next_reference(current_organization) }
    redirect_to project_path(project), notice: "Imported #{project.project_lines.size} BOM lines. Review the matches below."
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence.presence || "Could not import that BOM."
  end

  # Name, description and revision label; the lines are edited one by one.
  def update
    if @project.update(params.require(:project).permit(:name, :description, :revision))
      redirect_to project_path(@project), notice: "Project updated."
    else
      redirect_to project_path(@project),
        alert: @project.errors.full_messages.to_sentence,
        inertia: { errors: inertia_errors(@project, as: :project) }
    end
  end

  # Copies the project and its lines into a new draft labelled with the next
  # revision (or the one typed), to start revision B without touching A.
  def duplicate
    revision = params[:revision].to_s.strip.presence || @project.next_revision
    copy = @project.duplicate_as_revision(revision: revision)
    copy.save_with_generated_reference! { Project.next_reference(current_organization) }
    redirect_to project_path(copy), notice: "Revision #{copy.revision} created from #{@project.reference || @project.name}."
  rescue ActiveRecord::RecordInvalid
    redirect_to project_path(@project), alert: copy.errors.full_messages.to_sentence.presence || "Could not duplicate this project."
  end

  # Confirming also reserves the BOM when the organization uses reservations.
  def confirm
    reserve = current_organization.stock_reservations_enabled
    @project.update!(status: "confirmed", checked_at: Time.current, reserved_at: (Time.current if reserve))
    redirect_to project_path(@project), notice: reserve ? "Matches confirmed and stock reserved." : "Matches confirmed."
  end

  def reserve
    unless current_organization.stock_reservations_enabled && @project.confirmed?
      redirect_to project_path(@project), alert: "Only a confirmed project can reserve stock, with reservations turned on in Settings."
      return
    end

    @project.reserve!
    redirect_to project_path(@project), notice: "Stock reserved for this project."
  end

  def release
    @project.release_reservation!
    redirect_to project_path(@project), notice: "Reservation released."
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

  # Consumes the required quantity of every matched line from stock, for
  # +kits+ copies of the project (1 by default), recording an "out" movement per
  # source location and a ProjectBuild those movements point at. Only allowed
  # when the project is fully buildable for that many kits, so we never leave a
  # kit half-deducted.
  #
  # Building the same kit again is legitimate, but a double click or a replayed
  # request must not deduct it twice. The page posts the builds_count it showed;
  # the build only goes ahead if bumping that exact count succeeds — an atomic
  # compare-and-increment, so a second, stale submission matches no row.
  def build
    kits = params[:kits].to_s.presence&.to_i || 1
    unless kits.between?(1, MAX_BUILD_KITS)
      redirect_to project_path(@project), alert: "Build between 1 and #{MAX_BUILD_KITS} kits at a time."
      return
    end

    unless @project.buildable?(kits: kits)
      message = kits == 1 ? "This project isn't buildable yet — resolve shortfalls and unmatched lines first." : "There isn't enough stock to build #{kits} kits."
      redirect_to project_path(@project), alert: message
      return
    end

    required = @project.required_by_part(kits: kits)
    built = ActiveRecord::Base.transaction do
      now = Time.current
      claimed = Project.where(id: @project.id, builds_count: params[:builds_count].to_s.presence&.to_i)
        .update_all([ "builds_count = builds_count + ?, last_built_at = ?, updated_at = ?", kits, now, now ])
      raise ActiveRecord::Rollback if claimed.zero?

      build = @project.project_builds.create!(
        user: current_user, quantity: kits, built_at: now, note: params[:note].to_s.strip.presence
      )
      required.each { |part, quantity| deduct_part_stock(part, quantity, build) }
      # The build consumed what was reserved; reserve again for another kit.
      @project.release_reservation!
      true
    end

    unless built
      redirect_to project_path(@project), alert: "This kit was already built from this page. Reload to build another one."
      return
    end

    kit_text = kits == 1 ? "" : " (#{kits} kits)"
    redirect_to project_path(@project), notice: "Stock deducted for #{required.size} reference#{'s' if required.size != 1}#{kit_text}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: "Could not deduct stock: #{e.record.errors.full_messages.to_sentence}."
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  # A project started by hand: a name and no BOM yet; lines are added on its page.
  def create_empty
    name = params[:name].to_s.strip
    return redirect_to(projects_path, alert: "Give the project a name, or choose a BOM file to import.") if name.blank?

    project = current_organization.projects.new(
      name: name, description: params[:description].to_s.strip.presence, revision: params[:revision].to_s.strip.presence, status: "draft"
    )
    project.save_with_generated_reference! { Project.next_reference(current_organization) }
    redirect_to project_path(project), notice: "Project created. Add its parts below."
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence
  end

  def set_project
    @project = current_organization.projects
      .includes(project_lines: { part: [ :part_storages, { part_suppliers: :supplier } ] })
      .find(params[:id])
  end

  # Draws +quantity+ of +part+ down across its positive-stock locations,
  # emitting an "out" StockMovement for each source touched. Called once per
  # part, so the preloaded storage quantities are still current.
  def deduct_part_stock(part, quantity, build)
    remaining = quantity

    part.part_storages.select { |ps| ps.quantity.positive? }.each do |storage|
      break if remaining <= 0

      take = [ storage.quantity, remaining ].min
      current_organization.stock_movements.create!(
        part: part, storage_location: storage.storage_location, user: current_user,
        movement_type: "out", quantity_delta: -take, reason: "Build #{@project.reference}",
        project_build: build
      )
      remaining -= take
    end
  end

  def serialize_project_summary(project)
    {
      id: project.id,
      name: project.name,
      reference: project.reference,
      revision: project.revision,
      status: project.status,
      reserved: project.reserving?,
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
      description: project.description,
      reference: project.reference,
      revision: project.revision,
      next_revision: project.next_revision,
      status: project.status,
      reservations_enabled: current_organization.stock_reservations_enabled,
      reserved: project.reserving?,
      reserved_at: project.reserved_at&.iso8601,
      buildable: project.buildable?,
      short_count: project.short_lines.size,
      unmatched_count: project.unmatched_lines.size,
      checked_at: project.checked_at&.iso8601,
      builds_count: project.builds_count,
      last_built_at: project.last_built_at&.iso8601,
      builds: serialize_builds(project),
      lines: project.project_lines.map { |line| serialize_line(project, line, shortfalls) }
    }
  end

  # The latest builds with who built them and how many units of how many
  # references they took out of stock.
  def serialize_builds(project)
    builds = project.project_builds.recent.includes(:user).limit(BUILD_HISTORY_LIMIT).to_a
    totals = StockMovement.where(project_build_id: builds.map(&:id)).group(:project_build_id)
      .pluck(:project_build_id, Arel.sql("COUNT(DISTINCT part_id)"), Arel.sql("-SUM(quantity_delta)"))
      .to_h { |id, references, units| [ id, { references: references, units: units } ] }

    builds.map do |build|
      {
        id: build.id,
        quantity: build.quantity,
        built_at: build.built_at.iso8601,
        note: build.note,
        user: build.user && "#{build.user.firstname} #{build.user.lastname}".strip,
        references: totals.dig(build.id, :references) || 0,
        units: totals.dig(build.id, :units) || 0
      }
    end
  end

  # Shortfall and availability come from the project-wide per-part totals, so a
  # part listed on two lines isn't shown as available on each when its stock
  # only covers one.
  def serialize_line(project, line, shortfalls)
    shortfall = line.part ? shortfalls.fetch(line.part, 0) : 0
    {
      id: line.id,
      raw_reference: line.raw_reference,
      designation: line.designation,
      value: line.value,
      footprint: line.footprint,
      designators: line.designators,
      quantity: line.quantity,
      match_type: line.match_type,
      in_stock: line.in_stock,
      reserved_elsewhere: line.part ? project.reserved_elsewhere.fetch(line.part.id, 0) : 0,
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

# frozen_string_literal: true

class ProjectsController < ApplicationController
  include Auth
  include OptionListSerializers

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update duplicate confirm reserve release create_purchase_orders build destroy]
  before_action :set_project, only: %i[show update duplicate confirm reserve release create_purchase_orders build destroy]

  # Most kits one build can deduct at once.
  MAX_BUILD_KITS = 1_000
  # Builds listed on the project page, newest first.
  BUILD_HISTORY_LIMIT = 50

  def index
    projects = current_organization.projects
      .includes(:kicad_files_attachments, project_lines: { part: :part_storages })
      .recent
    # One tree reader for the whole list, so sub-assemblies and reservations are read once.
    structure = ProjectStructure.new(current_organization)
    used_as_assembly = ProjectLine.where(subproject_id: projects.map(&:id)).distinct.pluck(:subproject_id).to_set

    render inertia: "projects/index", props: {
      projects: projects.map do |project|
        project.structure = structure
        serialize_project_summary(project).merge(used_as_assembly: used_as_assembly.include?(project.id))
      end,
      github_token_configured: current_organization.github_token.present?
    }
  end

  def show
    render inertia: "projects/show", props: {
      project: serialize_project(@project),
      # Lightweight pick-list for the review UI's re-match combobox.
      parts: current_organization.parts.alphabetical.map do |part|
        { id: part.id, reference: part.reference, name: part.name, mpn: part.mpn, sku: part.sku }
      end,
      # Projects this one can use as a sub-assembly: not itself, nor one that uses it.
      subproject_options: serialize_subproject_options(@project),
      # Where the built item can go when the project has one.
      storage_locations: @project.output_part ? serialize_storage_locations : []
    }
  end

  def create
    uploads = Array(params[:files]).select { |upload| upload.respond_to?(:original_filename) }
    return create_from_kicad_files(uploads) if uploads.any?
    return create_from_github if params[:repository].present?

    file = params[:file]
    return create_empty unless file
    return redirect_to(projects_path, alert: BomParser.too_large_message) if BomParser.too_large?(file)

    name = params[:name].presence || File.basename(file.original_filename.to_s, ".*").presence || "Untitled project"

    begin
      lines = BomParser.parse(file.path)
    rescue CSV::MalformedCSVError
      return redirect_to(projects_path, alert: t("flash.projects.could_not_parse_that_file_as"))
    rescue Nokogiri::XML::SyntaxError, BomParser::Kicad::NotANetlist
      return redirect_to(projects_path, alert: t("flash.projects.could_not_read_that_file_as"))
    end

    if lines.empty?
      return redirect_to(projects_path, alert: t("flash.projects.that_file_has_no_usable_bom"))
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
    redirect_to project_path(project), notice: t("flash.projects.imported_bom_lines_review_the_matches", project_lines_count: project.project_lines.size)
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence.presence || t("flash.projects.could_not_import_that_bom")
  end

  # Name, description, revision label and built item; the lines are edited one by one.
  def update
    attributes = params.require(:project).permit(:name, :description, :revision, :output_part_id)
    if attributes.key?(:output_part_id)
      part_id = attributes.delete(:output_part_id)
      attributes[:output_part] = part_id.presence && current_organization.parts.find_by(id: part_id)
    end
    if @project.update(attributes)
      redirect_to project_path(@project), notice: t("flash.projects.updated")
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
    redirect_to project_path(copy), notice: t("flash.projects.revision_created", revision: copy.revision, source: @project.reference || @project.name)
  rescue ActiveRecord::RecordInvalid
    redirect_to project_path(@project), alert: copy.errors.full_messages.to_sentence.presence || "Could not duplicate this project."
  end

  # Confirming also reserves the BOM when the organization uses reservations.
  def confirm
    reserve = current_organization.stock_reservations_enabled
    @project.update!(status: "confirmed", checked_at: Time.current, reserved_at: (Time.current if reserve))
    redirect_to project_path(@project), notice: reserve ? t("flash.projects.matches_confirmed_and_stock_reserved") : t("flash.projects.matches_confirmed")
  end

  def reserve
    unless current_organization.stock_reservations_enabled && @project.confirmed?
      redirect_to project_path(@project), alert: t("flash.projects.only_a_confirmed_project_can_reserve")
      return
    end

    @project.reserve!
    redirect_to project_path(@project), notice: t("flash.projects.stock_reserved_for_this_project")
  end

  def release
    @project.release_reservation!
    redirect_to project_path(@project), notice: t("flash.projects.reservation_released")
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
        unit_price: (supplier_link.unit_price_for(quantity) || part.unit_price || 0).to_f
      }
    end

    if candidates.empty?
      redirect_to project_path(@project), alert: t("flash.projects.nothing_left_to_order_short_parts")
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
      notice: t("flash.purchase_orders_created", count: created, references: t("flash.references", count: references))
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: t("flash.projects.no_purchase_order_was_created", errors: e.record.errors.full_messages.to_sentence)
  end

  # Consumes the required quantity of every matched line from stock, for
  # +kits+ copies of the project (1 by default), recording an "out" movement per
  # source location and a ProjectBuild those movements point at. Only allowed
  # when the project is fully buildable for that many kits, so we never leave a
  # kit half-deducted. Phantom sub-assemblies are built along (their parts are
  # deducted); stocked ones are taken from stock as their built item. When the
  # project has a built item itself, the kits are added to stock as an "in"
  # movement into the chosen zone (else the part's first zone).
  #
  # Building the same kit again is legitimate, but a double click or a replayed
  # request must not deduct it twice. The page posts the builds_count it showed;
  # the build only goes ahead if bumping that exact count succeeds — an atomic
  # compare-and-increment, so a second, stale submission matches no row.
  def build
    kits = params[:kits].to_s.presence&.to_i || 1
    unless kits.between?(1, MAX_BUILD_KITS)
      redirect_to project_path(@project), alert: t("flash.projects.build_kits_between", max: MAX_BUILD_KITS)
      return
    end

    unless @project.buildable?(kits: kits)
      message = kits == 1 ? t("flash.projects.this_project_isn_t_buildable_yet") : t("flash.projects.not_enough_stock_for_kits", kits: kits)
      redirect_to project_path(@project), alert: message
      return
    end

    output_location = output_storage_location
    if @project.output_part && output_location.nil?
      redirect_to project_path(@project), alert: t("flash.projects.pick_a_zone_for_the_built_item", part: @project.output_part.name)
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
      if output_location
        current_organization.stock_movements.create!(
          part: @project.output_part, storage_location: output_location, user: current_user,
          movement_type: "in", quantity_delta: kits, reason: "Build #{@project.reference}", project_build: build
        )
      end
      # The build consumed what was reserved; reserve again for another kit.
      @project.release_reservation!
      true
    end

    unless built
      redirect_to project_path(@project), alert: t("flash.projects.this_kit_was_already_built_from")
      return
    end

    notice = t("flash.projects.stock_deducted", count: required.size)
    notice = t("flash.projects.stock_deducted_kits", count: required.size, kits: kits) if kits > 1
    notice = "#{notice} #{t('flash.projects.built_item_added', count: kits, part: @project.output_part.name)}" if output_location
    redirect_to project_path(@project), notice: notice
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: t("flash.projects.could_not_deduct_stock", errors: e.record.errors.full_messages.to_sentence)
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: t("flash.projects.project_deleted")
  end

  private

  # A project made from its KiCad files (loose or zipped): they are attached,
  # and the BOM is read from the schematics among them.
  def create_from_kicad_files(uploads)
    if (error = ProjectKicadFiles.upload_error(uploads))
      return redirect_to(projects_path, alert: error)
    end

    lines = ProjectKicadFiles.bom_lines(ProjectKicadFiles.upload_files(uploads))
    filenames = uploads.map(&:original_filename)
    project = current_organization.projects.new(
      name: params[:name].presence || ProjectKicadFiles.project_name(filenames) || "Untitled project", status: "draft"
    )
    project.build_bom_lines(lines)
    project.kicad_files.attach(ProjectKicadFiles.attachables(uploads))
    project.save_with_generated_reference! { Project.next_reference(current_organization) }

    notice =
      if lines.any?
        "Imported #{project.project_lines.size} BOM lines from the schematic. Review the matches below."
      else
        "Project created with its files. No schematic (.kicad_sch) among them, so the BOM is empty."
      end
    redirect_to project_path(project), notice: notice
  rescue ProjectKicadFiles::Unreadable => e
    redirect_to projects_path, alert: e.message
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence.presence || "Could not create that project."
  end

  # A project started by hand: a name and no BOM yet; lines are added on its page.
  def create_empty
    name = params[:name].to_s.strip
    return redirect_to(projects_path, alert: t("flash.projects.name_or_file")) if name.blank?

    project = current_organization.projects.new(
      name: name, description: params[:description].to_s.strip.presence, revision: params[:revision].to_s.strip.presence, status: "draft"
    )
    project.save_with_generated_reference! { Project.next_reference(current_organization) }
    redirect_to project_path(project), notice: t("flash.projects.created_empty")
  rescue ActiveRecord::RecordInvalid
    redirect_to projects_path, alert: project.errors.full_messages.to_sentence
  end

  # A project linked to a GitHub repository, made with the KiCad files and BOM
  # fetched from it. Nothing is kept when the fetch fails.
  def create_from_github
    attributes = ProjectGithubController.link_attributes(params)
    project = current_organization.projects.new(status: "draft", **attributes)
    project.name = params[:name].presence || project.github_path&.split("/")&.last || project.github_repository.to_s.split("/").last
    return redirect_to(projects_path, alert: project.errors.full_messages.to_sentence) unless project.valid?

    flash = nil
    ActiveRecord::Base.transaction do
      project.save_with_generated_reference! { Project.next_reference(current_organization) }
      flash = ProjectGithubController.sync_flash(project)
      raise ActiveRecord::Rollback if flash[:alert]
    end
    return redirect_to(projects_path, alert: flash[:alert]) if flash[:alert]

    redirect_to project_path(project), notice: flash[:notice]
  end

  def set_project
    @project = current_organization.projects
      .includes({ kicad_files_attachments: :blob }, { output_part: :part_storages },
                project_lines: [ :subproject, { part: [ :part_storages, { part_suppliers: :supplier } ] } ])
      .find(params[:id])
  end

  # The zone a build puts the built item in: the one picked in the build
  # dialog, else the part's first zone. Nil when the project has no built item.
  def output_storage_location
    return unless @project.output_part

    if params[:storage_location_id].present?
      current_organization.storage_locations.find_by(id: params[:storage_location_id])
    else
      @project.output_part.fallback_storage_location
    end
  end

  # Every other project, minus the ones that use this one (a loop).
  def serialize_subproject_options(project)
    excluded = ProjectStructure.ancestor_ids(project.id) << project.id
    current_organization.projects.where.not(id: excluded.to_a).includes(:output_part).order(:name, :revision).map do |option|
      { id: option.id, name: option.name, reference: option.reference, revision: option.revision, stocked: option.output_part.present? }
    end
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
      unmatched_count: project.unmatched_lines.size + project.incomplete_assembly_lines.size,
      assembly_count: project.subassembly_lines.size,
      checked_at: project.checked_at&.iso8601,
      created_at: project.created_at.iso8601,
      file_count: project.kicad_files.size,
      github_repository: project.github_repository
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
      incomplete_assembly_count: project.incomplete_assembly_lines.size,
      checked_at: project.checked_at&.iso8601,
      builds_count: project.builds_count,
      output_part: project.output_part && {
        id: project.output_part.id, reference: project.output_part.reference, name: project.output_part.name,
        in_stock: project.output_part.total_quantity,
        storage_location_id: project.output_part.fallback_storage_location&.id
      },
      used_in: serialize_used_in(project),
      assembly_parts: serialize_assembly_parts(project, shortfalls),
      last_built_at: project.last_built_at&.iso8601,
      builds: serialize_builds(project),
      lines: project.project_lines.map { |line| serialize_line(project, line, shortfalls) },
      files: project.kicad_files.map { |file| serialize_file(file) },
      files_have_schematics: ProjectKicadFiles.schematics?(project.kicad_files.map { |file| file.filename.to_s }),
      github: serialize_github(project),
      github_token_configured: current_organization.github_token.present?
    }
  end

  def serialize_github(project)
    return unless project.github_linked?

    {
      repository: project.github_repository,
      ref: project.github_ref,
      path: project.github_path,
      location: project.github_location,
      url: project.github_url,
      synced_sha: project.github_synced_sha,
      synced_at: project.github_synced_at&.iso8601,
      commit_url: project.github_synced_sha && "https://github.com/#{project.github_repository}/commit/#{project.github_synced_sha}"
    }
  end

  def serialize_file(file)
    {
      id: file.id,
      filename: file.filename.to_s,
      byte_size: file.byte_size,
      created_at: file.created_at.iso8601,
      url: stored_file_path_for(file),
      from_github: ProjectGithubSync.snapshot?(file)
    }
  end

  # The latest builds with who built them and how many units of how many
  # references they took out of stock.
  def serialize_builds(project)
    builds = project.project_builds.recent.includes(:user).limit(BUILD_HISTORY_LIMIT).to_a
    totals = StockMovement.where(project_build_id: builds.map(&:id)).where(quantity_delta: ...0).group(:project_build_id)
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

  # Projects using this one as a sub-assembly, with how many per kit.
  def serialize_used_in(project)
    project.used_in_lines.includes(:project).group_by(&:project).sort_by { |parent, _| [ parent.name, parent.revision.to_s ] }.map do |parent, lines|
      { id: parent.id, name: parent.name, reference: parent.reference, revision: parent.revision, quantity: lines.sum(&:quantity) }
    end
  end

  # The parts the sub-assembly lines bring for one kit (expanded for phantom
  # sub-assemblies, the built item for stocked ones), with availability.
  def serialize_assembly_parts(project, shortfalls)
    project.assembly_requirements.sort_by { |part, _| part.name.downcase }.map do |part, entry|
      shortfall = shortfalls.fetch(part, 0)
      {
        part: { id: part.id, reference: part.reference, name: part.name },
        quantity: entry[:quantity],
        line_ids: entry[:line_ids],
        in_stock: part.total_quantity,
        reserved_elsewhere: project.reserved_elsewhere.fetch(part.id, 0),
        shortfall: shortfall,
        available: shortfall.zero?
      }
    end
  end

  # Shortfall and availability come from the project-wide per-part totals, so a
  # part listed on two lines isn't shown as available on each when its stock
  # only covers one.
  def serialize_line(project, line, shortfalls)
    return serialize_assembly_line(project, line, shortfalls) if line.assembly?

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
      },
      assembly: nil
    }
  end

  # A sub-assembly line: complete or not, and how many of the parts it brings are short.
  def serialize_assembly_line(project, line, shortfalls)
    subproject = line.subproject
    brought = project.assembly_requirements.select { |_part, entry| entry[:line_ids].include?(line.id) }.keys
    short = brought.count { |part| shortfalls.fetch(part, 0).positive? }
    stocked_part = brought.first if project.structure.output_part_id(subproject.id)
    {
      id: line.id,
      raw_reference: line.raw_reference,
      designation: line.designation,
      value: line.value,
      footprint: line.footprint,
      designators: line.designators,
      quantity: line.quantity,
      match_type: line.match_type,
      in_stock: stocked_part&.total_quantity || 0,
      reserved_elsewhere: stocked_part ? project.reserved_elsewhere.fetch(stocked_part.id, 0) : 0,
      shortfall: stocked_part ? shortfalls.fetch(stocked_part, 0) : short,
      available: short.zero? && project.structure.complete_assembly?(subproject.id),
      part: nil,
      assembly: {
        id: subproject.id,
        name: subproject.name,
        reference: subproject.reference,
        revision: subproject.revision,
        stocked: stocked_part.present?,
        output_part: stocked_part && { id: stocked_part.id, reference: stocked_part.reference, name: stocked_part.name },
        complete: project.structure.complete_assembly?(subproject.id),
        parts_count: brought.size,
        short_parts: short
      }
    }
  end
end

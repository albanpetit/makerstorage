class Project < ApplicationRecord
  # Activity log (Auditable).
  audited ignore: %i[checked_at builds_count last_built_at github_synced_sha github_synced_at]

  include GeneratedReference
  include AttachmentValidation

  # Associations
  belongs_to :organization
  has_many :project_lines, dependent: :destroy
  has_many :project_builds, dependent: :destroy
  # Lines of other projects using this one as a sub-assembly (ProjectStructure).
  # Deleting the project turns them into free-text lines (see #unlink_assembly_lines).
  has_many :used_in_lines, class_name: "ProjectLine", foreign_key: :subproject_id, inverse_of: :subproject, dependent: nil
  # The inventory part a built kit becomes (optional): building credits it, and a
  # parent project takes it from stock instead of this project's parts.
  belongs_to :output_part, class_name: "Part", optional: true
  accepts_nested_attributes_for :project_lines
  # The project's design files: KiCad files or a ZIP of the project folder.
  has_many_attached :kicad_files

  # Constants
  STATUSES = %w[draft confirmed].freeze

  # KiCad files are plain text that content sniffing can't tell apart, so they
  # are typed by name on upload (see .kicad_content_type) and always served as
  # downloads.
  KICAD_FILE_TYPE = "application/x-kicad"
  ZIP_TYPE = "application/zip"
  KICAD_EXTENSIONS = %w[.kicad_pro .kicad_sch .kicad_pcb .kicad_sym .kicad_mod .kicad_prl .kicad_dru .kicad_wks].freeze
  KICAD_FILENAMES = %w[sym-lib-table fp-lib-table].freeze
  MAX_KICAD_FILES = 30
  MAX_KICAD_FILE_SIZE = 50.megabytes

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true
  validates_attachment :kicad_files, content_types: [ KICAD_FILE_TYPE, ZIP_TYPE ], max_size: MAX_KICAD_FILE_SIZE
  validate :kicad_files_count_within_limit
  validate :output_part_must_belong_to_same_organization
  validates :description, length: { maximum: 255 }
  validates :revision, length: { maximum: 20 }
  validates :github_repository, format: { with: GithubClient::REPOSITORY_FORMAT, message: "must look like owner/name" }, allow_blank: true
  validates :github_ref, length: { maximum: 255 }, format: { without: /\s|\.\./, message: "isn't a valid branch, tag or commit" }, allow_blank: true
  validates :github_path, length: { maximum: 255 }, format: { without: %r{(\A|/)\.\.(/|\z)}, message: "can't go up a folder" }, allow_blank: true

  before_destroy :unlink_assembly_lines

  normalizes :github_repository, with: ->(value) { value.strip.delete_suffix(".git").presence }
  normalizes :github_ref, with: ->(value) { value.strip.presence }
  normalizes :github_path, with: ->(value) { value.strip.gsub(%r{\A[/.]*/|/+\z}, "").squeeze("/").presence }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  # Confirmed projects currently holding their BOM quantities (see #reserving?).
  scope :reserving, -> { where(status: "confirmed").where.not(reserved_at: nil) }

  # Quantity held per part id by the organization's reserving projects. Empty
  # when the organization has reservations turned off. +except+ leaves one
  # project out; if that project is itself reserving, only the projects that
  # reserved before it count (first come, first served), so two projects never
  # both count each other's claim and over-order the same stock.
  #
  # A project's claim covers its sub-assemblies: their parts when they're
  # phantom, their built item when they're stocked (see ProjectStructure).
  # Pass a shared +structure+ when checking many projects in one request: the
  # reserving projects and their trees are then read once.
  def self.reserved_quantities(organization, part_ids: nil, except: nil, structure: ProjectStructure.new(organization))
    return {} unless organization.stock_reservations_enabled

    projects = structure.reserving_projects
    if except
      projects = projects.reject { |id, _| id == except.id }
      if except.reserving?
        projects = projects.select do |id, reserved_at|
          reserved_at < except.reserved_at || (reserved_at == except.reserved_at && id < except.id)
        end
      end
    end

    wanted = part_ids&.to_set
    projects.map(&:first).each_with_object(Hash.new(0)) do |project_id, totals|
      structure.part_quantities(project_id).each do |part_id, quantity|
        totals[part_id] += quantity if wanted.nil? || wanted.include?(part_id)
      end
    end.to_h
  end

  # The reserving projects holding +part+ (directly or through their
  # sub-assemblies), first come first served: [[project, quantity], ...].
  # Empty when the organization has reservations turned off.
  def self.reservations_of(organization, part)
    return [] unless organization.stock_reservations_enabled

    structure = ProjectStructure.new(organization)
    quantities = structure.reserving_projects.to_h { |id, _| [ id, structure.part_quantities(id)[part.id] ] }.compact
    projects = organization.projects.where(id: quantities.keys).index_by(&:id)
    quantities.map { |id, quantity| [ projects[id], quantity ] }
  end

  # The content type a KiCad file or project ZIP is stored under, from its
  # name; nil for any other file.
  def self.kicad_content_type(filename)
    name = File.basename(filename.to_s).downcase
    extension = File.extname(name)
    if KICAD_EXTENSIONS.include?(extension) || KICAD_FILENAMES.include?(name)
      KICAD_FILE_TYPE
    elsif extension == ".zip"
      ZIP_TYPE
    end
  end

  # Builds a human-readable, per-organization-unique reference of the form
  # "PRJ-YYYYMMDD-N", appending an incrementing suffix until one is free within
  # the organization (mirrors Order.next_reference).
  def self.next_reference(organization, date: Date.current)
    base = "PRJ-#{date.strftime('%Y%m%d')}"
    reference = "#{base}-1"
    suffix = 1
    while organization.projects.exists?(reference: reference)
      suffix += 1
      reference = "#{base}-#{suffix}"
    end
    reference
  end

  # Methods - Revisions

  # The label a copy of this project gets: the next one after its own ("A" →
  # "B", "v2" → "v3", "Z" → "AA"), skipping labels another project with the
  # same name already uses. A project without a label counts as "A".
  def next_revision
    used = organization.projects.where(name: name).where.not(revision: [ nil, "" ]).pluck(:revision).to_set(&:downcase)
    candidate = (revision.presence || "A").succ
    candidate = candidate.succ while used.include?(candidate.downcase)
    candidate
  end

  # A new draft project with this one's name, description, lines, design files
  # and GitHub link, labelled +revision+. Matches are kept as they are; status,
  # reservation and build history start over. The caller saves it (it needs a generated reference).
  def duplicate_as_revision(revision: next_revision)
    copy = organization.projects.new(name: name, description: description, revision: revision, status: "draft",
                                     **attributes.slice(*%w[github_repository github_ref github_path github_synced_sha github_synced_at]))
    copy.output_part_id = output_part_id
    project_lines.each do |line|
      copy.project_lines.build(
        line.attributes.slice(*%w[part_id subproject_id match_type raw_reference designation value footprint designators quantity])
      )
    end
    # The revision starts from the same design files: the blobs are shared, not copied.
    kicad_files.each { |file| copy.kicad_files.attach(file.blob) }
    copy
  end

  # Methods - Status
  def draft?
    status == "draft"
  end

  def confirmed?
    status == "confirmed"
  end

  # Methods - GitHub
  #
  # A project can take its KiCad files from a GitHub repository (optionally a
  # branch/tag/commit and a folder): ProjectGithubSync fetches them.

  def github_linked?
    github_repository.present?
  end

  # "owner/name", with the folder and ref when set: "owner/name/hw@v2".
  def github_location
    [ [ github_repository, github_path ].compact.join("/"), github_ref ].compact.join("@")
  end

  # The repository (or folder, at the ref) on github.com.
  def github_url
    return unless github_linked?

    base = "https://github.com/#{github_repository}"
    return base if github_ref.blank? && github_path.blank?

    "#{base}/tree/#{github_ref.presence || 'HEAD'}#{"/#{github_path}" if github_path.present?}"
  end

  # Drops the link; the files already fetched stay as files of the project.
  def unlink_github!
    update!(github_repository: nil, github_ref: nil, github_path: nil, github_synced_sha: nil, github_synced_at: nil)
  end

  # Methods - Reservation
  #
  # A confirmed project can reserve its BOM: the quantities it needs stop
  # counting as available for other projects until it is built (which consumes
  # them) or released. Reservations are bookkeeping only: they never touch the
  # ledger, and stock movements are never blocked by them.

  def reserving?
    confirmed? && reserved_at.present? && organization.stock_reservations_enabled
  end

  def reserve!
    update!(reserved_at: Time.current) if confirmed? && reserved_at.nil?
  end

  def release_reservation!
    update!(reserved_at: nil) if reserved_at.present?
  end

  # What other projects' reservations hold on this project's parts (its
  # sub-assemblies' included), by part id.
  def reserved_elsewhere
    @reserved_elsewhere ||= Project.reserved_quantities(
      organization, part_ids: required_by_part.keys.map(&:id), except: self, structure: structure
    )
  end

  # Stock this project can count on: physical stock minus what projects ahead
  # of it have reserved (never below zero, so a short reservation elsewhere
  # isn't ordered twice).
  def available_for(part)
    [ part.total_quantity - reserved_elsewhere.fetch(part.id, 0), 0 ].max
  end

  def reload(*)
    @reserved_elsewhere = nil
    @structure = nil
    @assembly_requirements = nil
    super
  end

  # Methods - Sub-assemblies
  #
  # A line can use another project as a sub-assembly (ProjectLine#subproject):
  # the parts it brings are counted in every availability decision below.

  # The organization's project tree reader; the projects list shares one.
  attr_writer :structure

  def structure
    @structure ||= ProjectStructure.new(organization)
  end

  # Lines that use another project.
  def subassembly_lines
    project_lines.select(&:assembly?)
  end

  # Sub-assembly lines that can't be built into this project yet: a phantom
  # sub-assembly that is empty, has unmatched lines, or goes too deep.
  def incomplete_assembly_lines
    subassembly_lines.reject { |line| structure.complete_assembly?(line.subproject_id) }
  end

  # Parts the sub-assembly lines bring, for one kit, with the line that brings
  # each: { part => { quantity:, line_ids: [...] } }. Parts are loaded with
  # their stock and suppliers.
  def assembly_requirements
    @assembly_requirements ||= begin
      totals = {}
      subassembly_lines.each do |line|
        structure.assembly_quantities(line.subproject_id).each do |part_id, quantity|
          entry = totals[part_id] ||= { quantity: 0, line_ids: [] }
          entry[:quantity] += quantity * line.quantity
          entry[:line_ids] << line.id
        end
      end
      known = project_lines.filter_map(&:part).index_by(&:id)
      known.reverse_merge!(structure.parts(totals.keys - known.keys))
      totals.filter_map { |part_id, entry| [ known[part_id], entry ] if known[part_id] }.to_h
    end
  end

  # Methods - Availability
  #
  # A BOM can list the same part on several lines, so availability is judged per
  # part against the summed requirement — checking each line alone would count
  # the same stock once per line.

  # Required quantity per matched part, summed across the lines that use it
  # and the sub-assemblies that bring it, for +kits+ copies of the project.
  def required_by_part(kits: 1)
    totals = project_lines.select(&:part).group_by(&:part).transform_values { |lines| lines.sum(&:quantity) * kits }
    assembly_requirements.each { |part, entry| totals[part] = totals.fetch(part, 0) + entry[:quantity] * kits }
    totals
  end

  # Parts whose available stock (see #available_for) can't cover their summed
  # requirement for +kits+ copies, with the missing quantity. Preload
  # `project_lines: { part: :part_storages }` to avoid an N+1.
  def shortfall_by_part(kits: 1)
    required_by_part(kits: kits).filter_map do |part, required|
      missing = required - available_for(part)
      [ part, missing ] if missing.positive?
    end.to_h
  end

  # Every line is matched (sub-assemblies complete) and every part's stock
  # covers its summed requirement for +kits+ copies. An empty project isn't
  # buildable — there is nothing to build.
  def buildable?(kits: 1)
    project_lines.any? && unmatched_lines.empty? && incomplete_assembly_lines.empty? && shortfall_by_part(kits: kits).empty?
  end

  # Lines whose part is short of the project's summed requirement, and
  # sub-assembly lines bringing a short part.
  def short_lines
    short_parts = shortfall_by_part.keys
    from_assemblies = short_parts.flat_map { |part| assembly_requirements.dig(part, :line_ids) || [] }.to_set
    project_lines.select { |line| line.part.in?(short_parts) || from_assemblies.include?(line.id) }
  end

  # Lines that couldn't be matched to any inventory part or project.
  def unmatched_lines
    project_lines.select { |line| line.part.nil? && !line.assembly? }
  end

  # Methods - BOM import

  # Adds a line per parsed BOM line (BomParser's hashes), matched against the
  # organization's parts. +manual+ maps BomParser.line_key to a part chosen by
  # hand earlier, which wins over the matcher.
  def build_bom_lines(lines, manual: {})
    matcher = BomParser::Matcher.new(organization)
    lines.each do |line|
      part = manual[BomParser.line_key(line)]
      part, match_type = part ? [ part, "manual" ] : matcher.match(line)
      project_lines.build(
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
  end

  # Swaps the BOM for +lines+ (the design changed): parts picked by hand stay
  # on the lines that still describe the same component, and the project goes
  # back to draft, unreserved, since its matches need checking again.
  def replace_bom!(lines)
    manual = project_lines.select { |line| line.match_type == "manual" && line.part }
      .to_h { |line| [ BomParser.line_key(line), line.part ] }

    transaction do
      project_lines.destroy_all
      build_bom_lines(lines, manual: manual)
      update!(status: "draft", checked_at: nil, reserved_at: nil)
    end
  end

  private

  def output_part_must_belong_to_same_organization
    if output_part.present? && output_part.organization_id != organization_id
      errors.add(:output_part, :same_organization)
    end
  end

  # Other projects' lines using this one keep their name and quantity as a
  # free-text line, so their BOM still shows something is missing.
  def unlink_assembly_lines
    used_in_lines.update_all(subproject_id: nil, match_type: "none", updated_at: Time.current)
  end

  def kicad_files_count_within_limit
    if kicad_files.size > MAX_KICAD_FILES
      errors.add(:kicad_files, :too_many_files, count: MAX_KICAD_FILES)
    end
  end
end

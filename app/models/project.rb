class Project < ApplicationRecord
  include GeneratedReference
  include AttachmentValidation

  # Associations
  belongs_to :organization
  has_many :project_lines, dependent: :destroy
  has_many :project_builds, dependent: :destroy
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
  validates :description, length: { maximum: 255 }
  validates :revision, length: { maximum: 20 }
  validates :github_repository, format: { with: GithubClient::REPOSITORY_FORMAT, message: "must look like owner/name" }, allow_blank: true
  validates :github_ref, length: { maximum: 255 }, format: { without: /\s|\.\./, message: "isn't a valid branch, tag or commit" }, allow_blank: true
  validates :github_path, length: { maximum: 255 }, format: { without: %r{(\A|/)\.\.(/|\z)}, message: "can't go up a folder" }, allow_blank: true

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
  def self.reserved_quantities(organization, part_ids: nil, except: nil)
    return {} unless organization.stock_reservations_enabled

    lines = ProjectLine.joins(:project).merge(organization.projects.reserving).where.not(part_id: nil)
    lines = lines.where(part_id: part_ids) unless part_ids.nil?
    if except
      lines = lines.where.not(project_id: except.id)
      if except.reserving?
        lines = lines.where("projects.reserved_at < :at OR (projects.reserved_at = :at AND projects.id < :id)",
                            at: except.reserved_at, id: except.id)
      end
    end
    lines.group(:part_id).sum(:quantity)
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
    project_lines.each do |line|
      copy.project_lines.build(
        line.attributes.slice(*%w[part_id match_type raw_reference designation value footprint designators quantity])
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

  # What other projects' reservations hold on this project's parts, by part id.
  def reserved_elsewhere
    @reserved_elsewhere ||= Project.reserved_quantities(
      organization, part_ids: project_lines.filter_map(&:part_id).uniq, except: self
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
    super
  end

  # Methods - Availability
  #
  # A BOM can list the same part on several lines, so availability is judged per
  # part against the summed requirement — checking each line alone would count
  # the same stock once per line.

  # Required quantity per matched part, summed across the lines that use it,
  # for +kits+ copies of the project.
  def required_by_part(kits: 1)
    project_lines.select(&:part).group_by(&:part).transform_values { |lines| lines.sum(&:quantity) * kits }
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

  # Every line is matched and every part's stock covers its summed requirement
  # for +kits+ copies. An empty project isn't buildable — there is nothing to build.
  def buildable?(kits: 1)
    project_lines.any? && unmatched_lines.empty? && shortfall_by_part(kits: kits).empty?
  end

  # Lines whose part is short of the project's summed requirement.
  def short_lines
    short_parts = shortfall_by_part.keys
    project_lines.select { |line| line.part.in?(short_parts) }
  end

  # Lines that couldn't be matched to any inventory part.
  def unmatched_lines
    project_lines.select { |line| line.part.nil? }
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

  def kicad_files_count_within_limit
    if kicad_files.size > MAX_KICAD_FILES
      errors.add(:kicad_files, :too_many_files, count: MAX_KICAD_FILES)
    end
  end
end

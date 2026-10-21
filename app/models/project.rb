class Project < ApplicationRecord
  include GeneratedReference

  # Associations
  belongs_to :organization
  has_many :project_lines, dependent: :destroy
  has_many :project_builds, dependent: :destroy
  accepts_nested_attributes_for :project_lines

  # Constants
  STATUSES = %w[draft confirmed].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true
  validates :description, length: { maximum: 255 }
  validates :revision, length: { maximum: 20 }

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

  # A new draft project with this one's name, description and lines, labelled
  # +revision+. Matches are kept as they are; status, reservation and build
  # history start over. The caller saves it (it needs a generated reference).
  def duplicate_as_revision(revision: next_revision)
    copy = organization.projects.new(name: name, description: description, revision: revision, status: "draft")
    project_lines.each do |line|
      copy.project_lines.build(
        line.attributes.slice(*%w[part_id match_type raw_reference designation value footprint designators quantity])
      )
    end
    copy
  end

  # Methods - Status
  def draft?
    status == "draft"
  end

  def confirmed?
    status == "confirmed"
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
end

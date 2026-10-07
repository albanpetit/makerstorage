class Project < ApplicationRecord
  include GeneratedReference

  # Associations
  belongs_to :organization
  has_many :project_lines, dependent: :destroy
  accepts_nested_attributes_for :project_lines

  # Constants
  STATUSES = %w[draft confirmed].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }

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

  # Methods - Status
  def draft?
    status == "draft"
  end

  def confirmed?
    status == "confirmed"
  end

  # Methods - Availability
  #
  # A BOM can list the same part on several lines, so availability is judged per
  # part against the summed requirement — checking each line alone would count
  # the same stock once per line.

  # Required quantity per matched part, summed across the lines that use it.
  def required_by_part
    project_lines.select(&:part).group_by(&:part).transform_values { |lines| lines.sum(&:quantity) }
  end

  # Parts whose stock can't cover their summed requirement, with the missing
  # quantity. Preload `project_lines: { part: :part_storages }` to avoid an N+1.
  def shortfall_by_part
    required_by_part.filter_map do |part, required|
      missing = required - part.total_quantity
      [ part, missing ] if missing.positive?
    end.to_h
  end

  # Every line is matched and every part's stock covers its summed requirement.
  # An empty project isn't buildable — there is nothing to build.
  def buildable?
    project_lines.any? && unmatched_lines.empty? && shortfall_by_part.empty?
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

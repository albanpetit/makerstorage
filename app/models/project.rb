class Project < ApplicationRecord
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
  # Every line has a matched part with enough stock to cover its required
  # quantity. An empty project isn't buildable — there is nothing to build.
  def buildable?
    project_lines.any? && project_lines.all?(&:available?)
  end

  # Lines that are matched to a part but short of the required quantity.
  def short_lines
    project_lines.select { |line| line.part.present? && line.shortfall.positive? }
  end

  # Lines that couldn't be matched to any inventory part.
  def unmatched_lines
    project_lines.select { |line| line.part.nil? }
  end
end

class Footprint < ApplicationRecord
  # Associations
  belongs_to :organization
  has_many :parts, dependent: :restrict_with_error

  # Active Storage
  has_one_attached :image
  include AttachmentValidation
  validates_attachment :image, content_types: AttachmentValidation::LOGO_TYPES, max_size: 2.megabytes

  # Constants
  MOUNTING_TYPES = %w[SMD Through-hole Both].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 50 }
  validates :name, uniqueness: { scope: :organization_id }
  validates :mounting_type, inclusion: { in: MOUNTING_TYPES }, allow_blank: true

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :smd, -> { where(mounting_type: "SMD") }
  scope :through_hole, -> { where(mounting_type: "Through-hole") }
  scope :commonly_used, -> {
    joins(:parts)
      .group("footprints.id")
      .order("COUNT(parts.id) DESC")
  }

  # Methods
  def smd?
    mounting_type == "SMD"
  end

  def through_hole?
    mounting_type == "Through-hole"
  end

  def has_image?
    image.attached?
  end
end

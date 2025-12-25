class Tag < ApplicationRecord
  # Associations
  belongs_to :organization
  has_many :part_tags, dependent: :destroy
  has_many :parts, through: :part_tags

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 50 }
  validates :name, uniqueness: { scope: :organization_id }
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }, allow_blank: true

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :most_used, -> {
    joins(:parts)
      .group("tags.id")
      .order("COUNT(parts.id) DESC")
  }
end

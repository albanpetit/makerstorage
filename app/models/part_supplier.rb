# frozen_string_literal: true

class PartSupplier < ApplicationRecord
  # Associations
  belongs_to :part
  belongs_to :supplier

  # Validations
  validates :supplier_id, uniqueness: { scope: :part_id, message: "is already linked to this part" }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validate :supplier_must_belong_to_same_organization

  # Scopes
  scope :preferred, -> { where(is_preferred: true) }
  scope :with_price, -> { where.not(unit_price: nil) }
  scope :by_price, -> { order(:unit_price) }

  # Callbacks
  before_save :ensure_single_preferred

  private

  def supplier_must_belong_to_same_organization
    return unless part && supplier

    if supplier.organization_id != part.organization_id
      errors.add(:supplier, "must belong to the same organization")
    end
  end

  # Ensure only one preferred supplier per part
  def ensure_single_preferred
    return unless is_preferred? && is_preferred_changed?

    PartSupplier.where(part_id: part_id, is_preferred: true)
                .where.not(id: id)
                .update_all(is_preferred: false)
  end
end

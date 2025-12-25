class Supplier < ApplicationRecord
  # Associations
  belongs_to :organization
  has_many :purchases, dependent: :restrict_with_error
  has_many :parts, foreign_key: :preferred_supplier_id, dependent: :nullify

  # Active Storage
  has_one_attached :logo

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :with_parts, -> { joins(:parts).distinct }

  # Methods
  def has_contact_info?
    email.present? || phone.present? || website.present?
  end

  def full_address
    [
      address_line1,
      address_line2,
      [ postcode, city ].compact.join(" "),
      country
    ].compact.reject(&:blank?).join(", ")
  end

  def has_complete_address?
    address_line1.present? && city.present? && country.present?
  end

  def has_logo?
    logo.attached?
  end
end

class Supplier < ApplicationRecord
  # Supported external catalog integrations (see SupplierCatalog). A supplier
  # tagged with one of these is the local record that a configured API
  # integration fills prices from, and is seeded for every organization.
  CATALOG_PROVIDERS = %w[mouser digikey].freeze

  # Canonical display name + website for each provider's seeded supplier.
  CATALOG_PROVIDER_DEFAULTS = {
    "mouser" => { name: "Mouser Electronics", website: "https://www.mouser.com" },
    "digikey" => { name: "DigiKey", website: "https://www.digikey.com" }
  }.freeze

  # Associations
  belongs_to :organization
  has_many :orders, dependent: :restrict_with_error
  has_many :part_suppliers, dependent: :destroy
  has_many :parts, through: :part_suppliers

  # Active Storage
  has_one_attached :logo
  include AttachmentValidation
  validates_attachment :logo, content_types: AttachmentValidation::LOGO_TYPES, max_size: 2.megabytes

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validates :catalog_provider, inclusion: { in: CATALOG_PROVIDERS }, allow_nil: true
  validates :catalog_provider, uniqueness: { scope: :organization_id }, allow_nil: true

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :with_parts, -> { joins(:parts).distinct }
  scope :catalog, -> { where.not(catalog_provider: nil) }

  # Returns the +organization+'s supplier for +provider+, creating it if absent,
  # as [supplier, created?]. Adopts a matching untagged supplier (same name)
  # left over from older seeds rather than creating a duplicate.
  def self.ensure_catalog_provider(organization, provider)
    provider = provider.to_s
    defaults = CATALOG_PROVIDER_DEFAULTS.fetch(provider)

    existing = organization.suppliers.find_by(catalog_provider: provider)
    return [ existing, false ] if existing

    adopted = organization.suppliers.find_by(name: defaults[:name])
    if adopted
      adopted.update!(catalog_provider: provider)
      return [ adopted, false ]
    end

    [ organization.suppliers.create!(catalog_provider: provider, **defaults), true ]
  end

  # Methods
  def catalog?
    catalog_provider.present?
  end
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

class Organization < ApplicationRecord
  # Associations - Memberships
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships

  # Associations - Data
  has_many :parts, dependent: :destroy
  has_many :storage_locations, dependent: :destroy
  has_many :stock_movements, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :footprints, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :suppliers, dependent: :destroy

  # Active Storage
  has_one_attached :logo

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true

  # Callbacks
  validate :must_have_at_least_one_owner, on: :update

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods - Members
  def owners
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: "owner" })
  end

  def admins
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: %w[owner admin] })
  end

  def members
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: "member" })
  end

  def member?(user)
    users.include?(user)
  end

  def owner?(user)
    organization_memberships.exists?(user: user, role: "owner")
  end

  def admin?(user)
    organization_memberships.exists?(user: user, role: %w[owner admin])
  end

  # Methods - Address
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

  def has_contact_info?
    email.present? || phone.present?
  end

  def has_logo?
    logo.attached?
  end

  # Methods - Stats
  def total_parts_count
    parts.count
  end

  def low_stock_parts_count
    parts.low_stock.count
  end

  def out_of_stock_parts_count
    parts.out_of_stock.count
  end

  def total_stock_value
    parts.sum("COALESCE(unit_price, 0) * COALESCE((SELECT SUM(quantity) FROM part_storages WHERE part_storages.part_id = parts.id), 0)")
  end

  private

  def must_have_at_least_one_owner
    if organization_memberships.owners.count.zero?
      errors.add(:base, "Organization must have at least one owner")
    end
  end
end

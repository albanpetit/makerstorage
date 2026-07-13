class Organization < ApplicationRecord
  # Set before the dependent-destroy cascade runs so a membership's last-owner
  # guard can tell "the whole org is going away" apart from "someone is removing
  # the sole owner", and allow the former. `prepend` puts it ahead of the
  # association's own dependent: :destroy callback.
  attr_accessor :being_destroyed

  before_destroy -> { self.being_destroyed = true }, prepend: true

  # Associations - Memberships
  has_many :organization_memberships, dependent: :destroy, inverse_of: :organization
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

  # Constants
  IPN_SEPARATORS = %w[- . _ /].freeze
  IPN_GENERATION_MODES = %w[incremental random category_sequence manual].freeze
  IPN_CHARSETS = %w[numeric alphanumeric].freeze
  CURRENCIES = %w[EUR USD GBP CHF].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validates :ipn_prefix, presence: true, length: { maximum: 6 }
  validates :ipn_separator, inclusion: { in: IPN_SEPARATORS }, allow_blank: true
  validates :ipn_generation_mode, inclusion: { in: IPN_GENERATION_MODES }
  validates :ipn_charset, inclusion: { in: IPN_CHARSETS }
  validates :ipn_digits, numericality: { only_integer: true, greater_than_or_equal_to: 3, less_than_or_equal_to: 8 }
  validates :ipn_next_sequence, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :default_low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Callbacks
  validate :must_have_at_least_one_owner, on: :update

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods - Members
  def owners
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: "owner" })
         .distinct
  end

  def admins
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: %w[owner admin] })
         .distinct
  end

  def members
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: "member" })
         .distinct
  end

  def viewers
    users.joins(:organization_memberships)
         .where(organization_memberships: { role: "viewer" })
         .distinct
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

  # Methods - IPN numbering
  #
  # The generation mode decides how the numeric segment is produced:
  #   incremental       — zero-padded running counter (ordered, predictable)
  #   category_sequence — same, but the category code is always included and the
  #                       counter is conceptually per-category (preview starts at 1)
  #   random            — a random draw from the configured charset (unpredictable)
  #   manual            — operator types the reference; this yields the suggested value
  # `sequence` seeds the numeric/random body so previews are stable and reproducible.
  def next_ipn(category_code: nil, sequence: ipn_next_sequence)
    include_category = ipn_generation_mode == "category_sequence" || (ipn_use_category_code && category_code.present?)
    resolved_category = category_code.presence || ("RES" if ipn_generation_mode == "category_sequence")

    body = ipn_generation_mode == "random" ? random_ipn_body(sequence) : sequence.to_s.rjust(ipn_digits, "0")

    [ ipn_prefix.presence, (resolved_category if include_category), body ].compact.join(ipn_separator)
  end

  def ipn_preview(category_code: nil, example_count: 3)
    start = ipn_generation_mode == "category_sequence" ? 1 : ipn_next_sequence
    effective_category = ipn_generation_mode == "category_sequence" ? (category_code.presence || "RES") : category_code

    {
      next: next_ipn(category_code: effective_category, sequence: start),
      examples: (1..example_count).map { |i| next_ipn(category_code: effective_category, sequence: start + i) }
    }
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
    parts.low_stock.length
  end

  def out_of_stock_parts_count
    parts.out_of_stock.length
  end

  def total_stock_value
    parts.sum("COALESCE(unit_price, 0) * COALESCE((SELECT SUM(quantity) FROM part_storages WHERE part_storages.part_id = parts.id), 0)")
  end

  def total_stock_units
    parts.joins(:part_storages).sum("part_storages.quantity")
  end

  def category_breakdown
    counts = parts.joins(:category).group("categories.name").count
    max = counts.values.max || 1
    counts.sort_by { |_, count| -count }.map do |name, count|
      { name: name, count: count, pct: (count.to_f / max * 100).round }
    end
  end

  private

  def random_ipn_body(seed)
    alphabet = ipn_charset == "alphanumeric" ? (("A".."Z").to_a + ("0".."9").to_a) : ("0".."9").to_a
    rng = Random.new(Integer(seed))
    Array.new(ipn_digits) { alphabet[rng.rand(alphabet.length)] }.join
  end

  def must_have_at_least_one_owner
    if organization_memberships.owners.count.zero?
      errors.add(:base, "Organization must have at least one owner")
    end
  end
end

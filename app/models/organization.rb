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
  has_many :orders, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :footprints, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :suppliers, dependent: :destroy

  # Active Storage
  has_one_attached :logo

  # Encrypted secrets - supplier catalog integration (see SupplierCatalog)
  encrypts :mouser_api_key
  encrypts :mouser_order_api_key
  encrypts :digikey_client_id
  encrypts :digikey_client_secret
  encrypts :digikey_access_token
  encrypts :digikey_refresh_token

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
  after_create :seed_catalog_suppliers

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

  # Renumbers every existing part with a freshly generated IPN using the current
  # config, replacing whatever they had — the companion to a mid-run format
  # change, which otherwise leaves old parts on the old format. No-op in manual
  # mode (nothing to generate). Parts are numbered in creation order from
  # sequence 1, and `ipn_next_sequence` is left pointing just past the last one
  # so new parts continue the run. Returns the number of parts renumbered.
  #
  # Clears every IPN up front so a value we're about to reuse can't collide with
  # an old one still sitting on another part, then draws each reference the same
  # way Part#assign_ipn does (skipping any already taken, e.g. random collisions).
  def reassign_ipns!
    return 0 if ipn_generation_mode == "manual"

    with_lock do
      parts.update_all(ipn: nil)
      sequence = 1
      count = 0

      parts.includes(:category).order(:created_at, :id).each do |part|
        candidate = next_ipn(category_code: part.category&.code, sequence: sequence)
        attempts = 0
        while attempts < 100 && parts.exists?(ipn: candidate)
          sequence += 1
          candidate = next_ipn(category_code: part.category&.code, sequence: sequence)
          attempts += 1
        end
        part.update_column(:ipn, candidate)
        sequence += 1
        count += 1
      end

      update_column(:ipn_next_sequence, sequence)
      count
    end
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

  # Methods - Supplier catalog integration
  # Whether an external supplier catalog (Mouser, DigiKey, ...) can be queried
  # for this org.
  def supplier_lookup_configured?
    mouser_api_key.present? || digikey_configured?
  end

  # DigiKey needs both halves of the OAuth2 client-credentials pair to work.
  def digikey_configured?
    digikey_client_id.present? && digikey_client_secret.present?
  end

  # Whether the Mouser Order/Cart API (push-to-cart, order import) can be used.
  def mouser_order_configured?
    mouser_order_api_key.present?
  end

  # Whether a DigiKey customer account is linked via the Authorization Code flow
  # (needed for the user-scoped Order Status API). The refresh token is the
  # durable half — the access token expires within the hour.
  def digikey_account_connected?
    digikey_refresh_token.present?
  end

  # Methods - Stats
  def total_parts_count
    parts.count
  end

  def low_stock_parts_count
    count_grouped(parts.low_stock)
  end

  def out_of_stock_parts_count
    count_grouped(parts.out_of_stock)
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

  # Counts the rows of a grouped/HAVING scope (e.g. `low_stock`, which groups by
  # part and filters on summed quantity) without loading the matched Part records
  # into memory. Wrapping the grouped query as a subquery lets the database
  # answer with a single `COUNT(*)` instead of us materializing the set to size
  # it — this runs on every authenticated Inertia render via `alerts_count`.
  def count_grouped(relation)
    Part.from(relation.select("parts.id"), :parts).count
  end

  # Every org starts with a supplier for each external catalog provider so the
  # lookup-driven price auto-fill has a target to link (see SupplierCatalog and
  # Supplier.ensure_catalog_provider).
  def seed_catalog_suppliers
    Supplier::CATALOG_PROVIDERS.each { |provider| Supplier.ensure_catalog_provider(self, provider) }
  end

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

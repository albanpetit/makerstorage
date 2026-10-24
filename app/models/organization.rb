class Organization < ApplicationRecord
  # Activity log (Auditable): settings changes. Secrets are logged as
  # "changed"; tokens refreshed or stamped behind the user's back are ignored.
  audited on: %i[update],
    ignore: %i[ipn_next_sequence notifications_sent_on digikey_access_token digikey_refresh_token
               digikey_token_expires_at kicad_token_created_at kicad_token_last_used_at
               onboarding_template onboarding_dismissed_at],
    secret: %i[mouser_api_key mouser_order_api_key digikey_client_id digikey_client_secret
               kicad_token_digest github_token anthropic_api_key]

  # Set before the dependent-destroy cascade runs so a membership's last-owner
  # guard can tell "the whole org is going away" apart from "someone is removing
  # the sole owner", and allow the former. `prepend` puts it ahead of the
  # association's own dependent: :destroy callback.
  attr_accessor :being_destroyed

  before_destroy -> { self.being_destroyed = true }, prepend: true

  # Associations - Memberships
  has_many :organization_memberships, dependent: :destroy, inverse_of: :organization
  has_many :users, through: :organization_memberships
  # Access granted to MCP clients (Claude…) on this organization's data.
  has_many :oauth_authorizations, dependent: :delete_all

  # Associations - Data
  #
  # Declaration order is destroy order. Parts, storage locations, and suppliers
  # restrict deletion while movements, order lines, allocations, or orders still
  # point at them, so the records doing the pointing must go first — otherwise
  # destroying a populated organization silently returns false.
  # Stocktake lines point at the adjustments they wrote: they go first.
  has_many :stocktakes, dependent: :destroy
  has_many :stock_movements, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :loans, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :parts, dependent: :destroy
  has_many :storage_locations, dependent: :destroy
  has_many :categories, dependent: :destroy
  # After parts and categories, whose parameters and templates point at them.
  has_many :parameter_definitions, dependent: :destroy
  has_many :footprints, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :suppliers, dependent: :destroy
  # Settings rather than inventory: kept by a reset, not carried by a merge.
  has_many :label_printers, dependent: :destroy
  # Last: deleting an organization writes no events (see #destroy), but this
  # clears any the cascade above would leave behind.
  has_many :activity_events, dependent: :delete_all

  # Active Storage
  has_one_attached :logo
  include AttachmentValidation
  validates_attachment :logo, content_types: AttachmentValidation::LOGO_TYPES, max_size: 2.megabytes

  # Encrypted secrets - supplier catalog integration (see SupplierCatalog)
  encrypts :mouser_api_key
  encrypts :mouser_order_api_key
  encrypts :digikey_client_id
  encrypts :digikey_client_secret
  encrypts :digikey_access_token
  encrypts :digikey_refresh_token
  # GitHub token for projects linked to a private repository (see GithubClient)
  encrypts :github_token
  # AI-assisted part entry (see PartExtraction)
  encrypts :anthropic_api_key

  # Constants
  IPN_SEPARATORS = %w[- . _ /].freeze
  IPN_GENERATION_MODES = %w[incremental random category_sequence manual box_bag].freeze
  IPN_CHARSETS = %w[numeric alphanumeric].freeze
  CURRENCIES = %w[EUR USD GBP CHF].freeze
  # The zones Settings offers (IANA names behind Rails' friendly zone names).
  TIMEZONES = ActiveSupport::TimeZone::MAPPING.values.uniq.sort.freeze
  # How often the email digest goes out: every morning, or Monday mornings.
  NOTIFICATION_FREQUENCIES = %w[daily weekly].freeze
  # Local hour (in the org's time zone) from which the day's digest is sent.
  NOTIFICATION_HOUR = 8

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: HTTP_URL_FORMAT }, allow_blank: true
  validates :ipn_prefix, presence: true, length: { maximum: 6 }
  validates :ipn_separator, inclusion: { in: IPN_SEPARATORS }, allow_blank: true
  validates :ipn_generation_mode, inclusion: { in: IPN_GENERATION_MODES }
  validates :ipn_charset, inclusion: { in: IPN_CHARSETS }
  validates :ipn_digits, numericality: { only_integer: true, greater_than_or_equal_to: 3, less_than_or_equal_to: 8 }
  validates :ipn_next_sequence, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INTEGER }
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :timezone, inclusion: { in: TIMEZONES }
  validates :default_low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_INTEGER }
  validates :notification_frequency, inclusion: { in: NOTIFICATION_FREQUENCIES }
  validates :ai_model, inclusion: { in: ->(_) { PartExtraction::MODELS.keys } }
  validates :default_loan_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Loan::MAX_DAYS }
  validates :consumption_window_days, numericality: { only_integer: true, greater_than_or_equal_to: PartConsumption::MIN_RATE_DAYS, less_than_or_equal_to: PartConsumption::MAX_DAYS }
  validates :threshold_cover_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: PartConsumption::MAX_DAYS }

  # Callbacks
  validate :must_have_at_least_one_owner, on: :update
  before_save :unlink_digikey_account, if: :digikey_app_replaced?
  after_create :seed_catalog_suppliers
  after_update :refresh_bag_codes!, if: -> { ipn_generation_mode == "box_bag" && saved_change_to_ipn_separator? }
  validate :bag_codes_stay_unique, if: -> { ipn_generation_mode == "box_bag" && will_save_change_to_ipn_separator? }

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Deleting the organization isn't logged, nor is the cascade of records it takes.
  def destroy
    ActivityEvent.without_recording { super }
  end

  # Methods - Reset
  #
  # The inventory associations a reset clears, in the destroy order above.
  DATA_ASSOCIATIONS = %i[stocktakes stock_movements projects loans orders parts storage_locations categories parameter_definitions footprints tags suppliers].freeze

  # Deletes every inventory record (stocktakes, movements, projects, loans, orders, parts, zones,
  # categories, parameters, footprints, tags, suppliers) and keeps the organization itself:
  # its settings, integrations, logo and members. The IPN counter starts over
  # and the catalog suppliers are seeded again, as for a new organization.
  # Returns the number of parts removed. Logged as one "reset" event, not one
  # per record deleted.
  def reset_data!
    transaction do
      lock!
      parts_count = parts.count

      ActivityEvent.without_recording do
        DATA_ASSOCIATIONS.each do |name|
          scope = public_send(name).reset
          # Trees go from their roots: destroying a parent takes its children with it.
          scope = scope.where(parent_id: nil) if name.in?(%i[storage_locations categories])
          scope.find_each { |record| record.destroy! }
        end

        update_columns(ipn_next_sequence: 1, notifications_sent_on: nil)
        seed_catalog_suppliers
      end
      ActivityEvent.record!(self, "reset", details: { "parts" => parts_count })
      parts_count
    end
  end

  # Methods - IPN numbering
  #
  # The generation mode decides how the numeric segment is produced:
  #   incremental       — zero-padded running counter (ordered, predictable)
  #   category_sequence — same, but the category code is always included and the
  #                       counter is conceptually per-category (preview starts at 1)
  #   random            — a random draw from the configured charset (unpredictable)
  #   manual            — operator types the reference; this yields the suggested value
  #   box_bag           — the reference is the bag holding the part (A-3), see
  #                       #free_bags and Part#claim_bag; not generated here
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
  # mode (nothing to generate). Writes what #ipn_reassignment_plan shows (see
  # there for the rules), recomputed under the lock, and in sequence modes
  # leaves `ipn_next_sequence` just past the last number so new parts continue
  # the run. Returns the number of parts whose IPN changed.
  #
  # Clears the IPNs being replaced up front so a value we're about to reuse
  # can't collide with an old one still sitting on another part.
  def reassign_ipns!(clear_unbagged: false)
    return 0 if ipn_generation_mode == "manual"

    with_lock do
      refresh_bag_codes! if ipn_generation_mode == "box_bag"
      plan = ipn_reassignment_plan(clear_unbagged: clear_unbagged)
      changes = plan[:entries].select { |entry| entry[:changed] }

      parts.where(id: changes.map { |entry| entry[:part].id }).update_all(ipn: nil)
      changes.each do |entry|
        columns = { ipn: entry[:to] }
        columns.merge!(bag_id: entry[:takes_bag].id, bag_assigned_at: Time.current) if entry[:takes_bag]
        entry[:part].update_columns(columns)
      end
      update_column(:ipn_next_sequence, plan[:next_sequence]) if plan[:next_sequence]
      ActivityEvent.record!(self, "update", self, details: { "ipns_reassigned" => changes.size }) if changes.any?
      changes.size
    end
  end

  # What #reassign_ipns! would do, without writing anything: one entry per part,
  # in creation order, as { part:, from:, to:, changed:, takes_bag: }, plus the
  # `next_sequence` the counter would be left at (sequence modes only).
  #
  # Sequence modes number every part from 1 in creation order, skipping any
  # reference already drawn in this run (random collisions), the way
  # Part#assign_ipn does. Box & bag mode gives each part holding a bag that
  # bag's code, lets a part without a bag but with stock in a bag nobody holds
  # take it (`takes_bag`), and leaves the other parts' IPNs alone — or clears
  # them with `clear_unbagged`. A kept IPN that one of those bag codes is about
  # to take is cleared too, since IPNs are unique.
  def ipn_reassignment_plan(clear_unbagged: false)
    case ipn_generation_mode
    when "manual" then { entries: [], next_sequence: nil }
    when "box_bag" then bag_ipn_reassignment_plan(clear_unbagged)
    else sequence_ipn_reassignment_plan
    end
  end

  def ipn_preview(category_code: nil, example_count: 3)
    if ipn_generation_mode == "box_bag"
      codes = free_bags.limit(example_count + 1).pluck(:code)
      return { next: codes.first, examples: codes.drop(1) }
    end

    start = ipn_generation_mode == "category_sequence" ? 1 : ipn_next_sequence
    effective_category = ipn_generation_mode == "category_sequence" ? (category_code.presence || "RES") : category_code

    {
      next: next_ipn(category_code: effective_category, sequence: start),
      examples: (1..example_count).map { |i| next_ipn(category_code: effective_category, sequence: start + i) }
    }
  end

  # Methods - Box & bag storage
  #
  # The bags (storage zones of type "bag", numbered inside a coded box) a new
  # part can take, in box then bag order: those no part holds, and those whose
  # part has been emptied out of them since it took the bag (stock back to 0
  # after at least one movement there). A part that took a bag but hasn't been
  # stocked yet keeps it. A bag still holding another part's stock is never
  # free, whoever holds it: `for_part` is the part asking, whose own stock
  # already sitting in a bag doesn't stop it from taking that bag.
  def free_bags(for_part: nil)
    held = parts.where.not(bag_id: nil).where(<<~SQL.squish)
      EXISTS (SELECT 1 FROM part_storages ps
              WHERE ps.part_id = parts.id AND ps.storage_location_id = parts.bag_id AND ps.quantity > 0)
      OR NOT EXISTS (SELECT 1 FROM stock_movements sm
                     WHERE sm.part_id = parts.id AND sm.storage_location_id = parts.bag_id
                       AND sm.created_at >= parts.bag_assigned_at)
    SQL

    storage_locations.bags
      .joins("INNER JOIN storage_locations boxes ON boxes.id = storage_locations.parent_id")
      .where.not(id: held.select(:bag_id))
      .where.not(id: PartStorage.where("part_storages.quantity > 0").where.not(part_id: for_part&.id).select(:storage_location_id))
      .order(Arel.sql("LOWER(boxes.code), storage_locations.position, storage_locations.id"))
  end

  # The codes in +renames+ (bag => new code) that would clash once written: with
  # each other, another zone's code, or the IPN of a part other than the bag's
  # own occupant (which takes the new code as its IPN), ignoring case. Checked
  # before a box rename or a separator change, which write the codes directly.
  def bag_code_clashes(renames)
    return [] if renames.empty?

    ids = renames.keys.map(&:id)
    codes = renames.values.map { |code| code.to_s.downcase }
    occupied_codes = renames.select { |bag, _| bag.bag_occupant }.values.map { |code| code.to_s.downcase }

    clashes = codes.tally.select { |_, count| count > 1 }.keys
    clashes += storage_locations.where.not(id: ids).where("LOWER(code) IN (?)", codes).pluck(:code)
    if occupied_codes.any?
      clashes += parts.where("LOWER(ipn) IN (?)", occupied_codes).where("bag_id IS NULL OR bag_id NOT IN (?)", ids).pluck(:ipn)
    end
    clashes.map(&:upcase).uniq.sort
  end

  # Rebuilds every bag's code from its box code, number and the current IPN
  # separator, and gives the parts holding them the new codes.
  def refresh_bag_codes!
    storage_locations.bags.includes(:parent, :bag_occupant).find_each do |bag|
      next unless bag.parent&.box?

      code = StorageLocation.bag_code(bag.parent.code, bag.position, ipn_separator)
      next if bag.code == code

      bag.update_column(:code, code)
      bag.bag_occupant&.update_column(:ipn, code)
    end
  end

  # Methods - Supplier catalog integration
  # Whether an external supplier catalog (Mouser, DigiKey, LCSC) can be queried
  # for this org.
  def supplier_lookup_configured?
    mouser_api_key.present? || digikey_configured? || lcsc_enabled?
  end

  # AI-assisted part entry: on once the organization has saved its own
  # Anthropic API key.
  def ai_entry_configured?
    anthropic_api_key.present?
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

  # Methods - Email notifications (see NotificationDigestJob)
  #
  # Whether any alert type is switched on for this organization.
  def email_notifications_enabled?
    notify_low_stock || notify_late_orders || notify_overdue_loans
  end

  # Whether this period's digest is still to be sent at `now`: from 8am local
  # time, once a day (daily) or on Mondays (weekly).
  def notification_digest_due?(now = Time.current)
    return false unless email_notifications_enabled?

    local = now.in_time_zone(timezone)
    return false if local.hour < NOTIFICATION_HOUR
    return false if notification_frequency == "weekly" && !local.monday?

    notifications_sent_on.nil? || notifications_sent_on < local.to_date
  end

  # Today's date in the organization's time zone.
  def local_date(now = Time.current)
    now.in_time_zone(timezone).to_date
  end

  # Members who get the digest: active and accepted, not opted out, with an
  # address they've confirmed (when this install verifies addresses).
  def notification_recipients
    users = User.where(id: organization_memberships.granting_access.where(email_notifications: true).select(:user_id))
    users = users.where.not(confirmed_at: nil) if User.email_verification?
    users
  end

  # Methods - Guided onboarding (dashboard, OrganizationTemplate)
  #
  # What onboarding_template holds when the owner chose to start empty.
  NO_TEMPLATE = "none"

  # Whether the dashboard offers to start from a template: nothing picked yet,
  # the first steps not put away, and nothing set up by hand (the catalog
  # suppliers every organization gets don't count).
  def template_choice_pending?
    onboarding_template.nil? && onboarding_dismissed_at.nil? && !demo? &&
      !categories.exists? && !storage_locations.exists? && !parts.exists?
  end

  # The "first steps" list, each step ticked from the organization's data
  # (nothing is ticked by hand). Inviting members is left out of a home
  # workshop.
  def onboarding_steps
    steps = {
      categories: categories.exists?,
      zones: storage_locations.exists?,
      supplier: suppliers.where(catalog_provider: nil).exists? || supplier_lookup_configured?,
      part: parts.exists?,
      stock: stock_movements.exists?,
      project: projects.exists?
    }
    steps[:members] = organization_memberships.count > 1 unless onboarding_template == "home_lab"
    steps
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

  def bag_codes_stay_unique
    renames = storage_locations.bags.includes(:parent, :bag_occupant).select { |bag| bag.parent&.box? }
      .to_h { |bag| [ bag, StorageLocation.bag_code(bag.parent.code, bag.position, ipn_separator) ] }
    clashes = bag_code_clashes(renames)
    errors.add(:ipn_separator, :bag_codes_taken, codes: clashes.to_sentence) if clashes.any?
  end

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

  # A linked DigiKey account's tokens were issued to one DigiKey app (Client
  # ID). Removing or replacing that app leaves them unusable — refreshing needs
  # the original client — yet the account would still show as connected, so
  # drop them with it. Rotating only the secret keeps the same app and link.
  # Saving new tokens alongside the client id (seeds, tests) is a fresh link.
  def digikey_app_replaced?
    will_save_change_to_digikey_client_id? && !will_save_change_to_digikey_refresh_token?
  end

  def unlink_digikey_account
    self.digikey_access_token = nil
    self.digikey_refresh_token = nil
    self.digikey_token_expires_at = nil
  end

  def sequence_ipn_reassignment_plan
    drawn = Set.new
    sequence = 1

    entries = parts.includes(:category).order(:created_at, :id).map do |part|
      candidate = next_ipn(category_code: part.category&.code, sequence: sequence)
      attempts = 0
      while attempts < 100 && drawn.include?(candidate.downcase)
        sequence += 1
        candidate = next_ipn(category_code: part.category&.code, sequence: sequence)
        attempts += 1
      end
      drawn << candidate.downcase
      sequence += 1
      ipn_plan_entry(part, candidate)
    end

    { entries: entries, next_sequence: sequence }
  end

  def bag_ipn_reassignment_plan(clear_unbagged)
    bags = storage_locations.bags.includes(:parent).index_by(&:id)
    code_of = ->(bag) { bag.parent&.box? ? StorageLocation.bag_code(bag.parent.code, bag.position, ipn_separator) : bag.code }
    all_parts = parts.order(:created_at, :id).includes(part_storages: :storage_location).to_a
    held = all_parts.filter_map(&:bag_id).to_set

    targets = all_parts.to_h do |part|
      next [ part, [ code_of.(bags.fetch(part.bag_id)), nil ] ] if part.bag_id

      storage = part.part_storages.find do |ps|
        ps.quantity.positive? && ps.storage_location.bag? && held.exclude?(ps.storage_location_id)
      end
      next [ part, [ nil, nil ] ] unless storage

      held << storage.storage_location_id
      bag = bags.fetch(storage.storage_location_id)
      [ part, [ code_of.(bag), bag ] ]
    end

    bag_codes = targets.values.filter_map { |code, _| code&.downcase }.to_set
    entries = targets.map do |part, (code, takes_bag)|
      code ||= part.ipn unless clear_unbagged || bag_codes.include?(part.ipn.to_s.downcase)
      ipn_plan_entry(part, code, takes_bag: takes_bag)
    end

    { entries: entries, next_sequence: nil }
  end

  def ipn_plan_entry(part, to, takes_bag: nil)
    { part: part, from: part.ipn, to: to, changed: part.ipn != to || takes_bag.present?, takes_bag: takes_bag }
  end

  def random_ipn_body(seed)
    alphabet = ipn_charset == "alphanumeric" ? (("A".."Z").to_a + ("0".."9").to_a) : ("0".."9").to_a
    rng = Random.new(Integer(seed))
    Array.new(ipn_digits) { alphabet[rng.rand(alphabet.length)] }.join
  end

  def must_have_at_least_one_owner
    if organization_memberships.owners.count.zero?
      errors.add(:base, :needs_owner)
    end
  end
end

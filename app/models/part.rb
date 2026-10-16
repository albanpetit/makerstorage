class Part < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :category
  belongs_to :footprint, optional: true
  # Box & bag numbering: the bag (a "bag" storage zone) this part occupies; its
  # code is the part's IPN. See #claim_bag.
  belongs_to :bag, class_name: "StorageLocation", optional: true, inverse_of: :bag_occupant

  has_many :part_storages, dependent: :destroy
  has_many :storage_locations, through: :part_storages

  has_many :stock_movements, dependent: :restrict_with_error

  has_many :part_tags, dependent: :destroy
  has_many :tags, through: :part_tags

  has_many :part_suppliers, dependent: :destroy
  has_many :suppliers, through: :part_suppliers
  accepts_nested_attributes_for :part_suppliers, allow_destroy: true, reject_if: :all_blank

  has_many :order_lines, dependent: :restrict_with_error
  has_many :orders, through: :order_lines

  # BOM lines matched to this part. Deleting the part un-matches them (back to
  # "none", like an unresolved import line) rather than blocking the delete or
  # leaving a dangling foreign key.
  has_many :project_lines, dependent: nil

  # Active Storage for images and datasheets
  has_many_attached :images
  has_one_attached :datasheet
  include AttachmentValidation
  validates_attachment :images, content_types: AttachmentValidation::IMAGE_TYPES, max_size: 10.megabytes
  # Matches SupplierCatalog::RemoteFile's download cap.
  validates_attachment :datasheet, content_types: AttachmentValidation::PDF_TYPES, max_size: 25.megabytes

  # Constants
  STATUSES = %w[active discontinued obsolete].freeze
  UNITS = %w[piece meter roll lot].freeze

  # Callbacks - convert empty strings to nil for unique indexed fields
  before_validation :normalize_blank_values
  # Assign the internal part number from the org's IPN config once the part is
  # actually being persisted (see #assign_ipn).
  before_create :assign_ipn
  # Box & bag mode: take the requested bag, or the first free one for a new
  # part, and stamp its code as the IPN. Before save so it also covers edits.
  before_save :claim_bag
  # Declared after the restrict_with_error associations above, so it only runs
  # once the part is actually allowed to go.
  before_destroy :unmatch_project_lines

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :mpn, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :sku, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :barcode, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :ipn, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :unit, presence: true, inclusion: { in: UNITS }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_stock_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_INTEGER }
  validates :target_stock, numericality: { greater_than: 0, less_than_or_equal_to: MAX_INTEGER }, allow_nil: true
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_INTEGER }, allow_nil: true
  # Hotlinked supplier image (e.g. Mouser, whose CDN blocks server-side download),
  # rendered directly in every member's browser: only https URLs on a supplier
  # image host (Makerstorage::SUPPLIER_IMAGE_HOSTS). Checked on change only, so a
  # part saved before the restriction stays editable (its image is just no
  # longer shown, see #hotlinked_image_url).
  validate :image_source_url_must_be_supplier_image, if: :image_source_url_changed?
  validate :category_must_belong_to_same_organization
  validate :footprint_must_belong_to_same_organization
  validate :bag_must_be_free, if: -> { bag_id.present? && will_save_change_to_bag_id? }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :discontinued, -> { where(status: "discontinued") }
  scope :obsolete, -> { where(status: "obsolete") }
  scope :rohs_compliant, -> { where(rohs_compliant: true) }

  # Low stock: total quantity < minimum threshold. Left join so a part that has
  # never been stocked (no part_storages row) counts as 0 — an inner join would
  # drop it, hiding it from alerts even though #low_stock? is true for it.
  scope :low_stock, -> {
    left_joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) < parts.min_stock_threshold")
  }

  # Critical stock: total quantity = 0
  scope :out_of_stock, -> {
    left_joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) = 0")
  }

  # Sufficient stock (left join, as above, so never-stocked parts are judged too)
  scope :sufficient_stock, -> {
    left_joins(:part_storages)
      .group("parts.id")
      .having("COALESCE(SUM(part_storages.quantity), 0) >= parts.min_stock_threshold")
  }

  # Extended search. Escape LIKE wildcards (%, _, \) in the user's query so they
  # match literally rather than acting as wildcards, and declare the escape char.
  scope :search, ->(query) {
    q = "%#{sanitize_sql_like(query)}%"
    where(
      "parts.name LIKE :q ESCAPE '\\' OR parts.mpn LIKE :q ESCAPE '\\' OR " \
      "parts.description LIKE :q ESCAPE '\\' OR parts.sku LIKE :q ESCAPE '\\' OR " \
      "parts.manufacturer LIKE :q ESCAPE '\\' OR parts.value LIKE :q ESCAPE '\\' OR " \
      "parts.barcode LIKE :q ESCAPE '\\'",
      q: q
    )
  }

  scope :alphabetical, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods - Images
  # +url+ when it points at a supplier image host (http is upgraded to https),
  # else nil. Controllers pass catalog lookup results through this, so an
  # unexpected host drops the image rather than refusing the part.
  def self.supplier_image_url(url)
    uri = URI.parse(url.to_s.strip)
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

    host = uri.host.downcase
    return nil unless Makerstorage::SUPPLIER_IMAGE_HOSTS.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }

    URI::HTTPS.build(host: host, path: uri.path.presence || "/", query: uri.query).to_s
  rescue URI::InvalidURIError
    nil
  end

  # The hotlinked image to show, if it is (still) an allowed supplier image.
  def hotlinked_image_url
    self.class.supplier_image_url(image_source_url) if image_source_url.present?
  end

  # Methods - Stock
  # Total stock across every storage location. When part_storages has already
  # been preloaded (via `includes`), sum the in-memory collection so callers on
  # list pages don't fire a fresh SUM query per part — the N+1 that bit the
  # parts index, alerts, suppliers, and dashboard. Falls back to a single
  # aggregate query when the association isn't loaded.
  def total_quantity
    if part_storages.loaded?
      part_storages.to_a.sum(&:quantity)
    else
      part_storages.sum(:quantity)
    end
  end

  # Where stock with no explicit target zone lands (e.g. an order line received
  # without a storage split): the first zone the part was ever stocked in. An
  # unordered `storage_locations.first` would let the database pick a different
  # zone from one receipt to the next. Uses preloaded part_storages when present.
  def fallback_storage_location
    storages = part_storages.loaded? ? part_storages.to_a : part_storages.includes(:storage_location)
    storages.min_by(&:id)&.storage_location
  end

  def low_stock?
    total_quantity < min_stock_threshold
  end

  def out_of_stock?
    total_quantity.zero?
  end

  def stock_status
    return :out_of_stock if out_of_stock?
    return :low_stock if low_stock?
    :sufficient
  end

  # Methods - Status
  def active?
    status == "active"
  end

  def discontinued?
    status == "discontinued"
  end

  def obsolete?
    status == "obsolete"
  end

  # Methods - References
  # Human-facing short reference used across scans, movements, alerts, etc.:
  # prefer the manufacturer part number, then the internal SKU, falling back to
  # the name so there is always something to display.
  def reference
    mpn.presence || sku.presence || name
  end

  # Methods - Suppliers
  def preferred_supplier
    part_suppliers.find_by(is_preferred: true)&.supplier
  end

  def preferred_part_supplier
    part_suppliers.find_by(is_preferred: true)
  end

  # Best price to put on an order line for +supplier_id+: the link to that
  # supplier, then the preferred supplier link, then the part's own cost basis.
  def order_unit_price(supplier_id)
    link = part_suppliers.find_by(supplier_id: supplier_id) || preferred_part_supplier
    link&.unit_price || unit_price
  end

  # Mirrors unit_price (the part's cost basis for stock valuation) onto the
  # preferred supplier's price. Called from PartSupplier when links change so
  # the two never drift. Leaves a manually-entered price untouched when there is
  # no preferred supplier price to sync from.
  def sync_unit_price_from_preferred!
    price = preferred_part_supplier&.unit_price
    return if price.nil? || unit_price == price

    update_column(:unit_price, price)
  end

  # Gives the part's bag back (box & bag numbering): the part keeps its stock
  # records but loses the bag and the IPN that was the bag's code. Leaves any
  # IPN that isn't the bag's (typed by hand, or from another mode) alone.
  def release_bag!
    return if bag.nil?

    update_columns(bag_id: nil, bag_assigned_at: nil, ipn: ipn.to_s.casecmp?(bag.code.to_s) ? nil : ipn)
  end

  private

  def unmatch_project_lines
    project_lines.update_all(part_id: nil, match_type: "none", updated_at: Time.current)
  end

  # Convert blank strings to nil for unique indexed fields
  def normalize_blank_values
    self.sku = nil if sku.blank?
    self.mpn = nil if mpn.blank?
    self.barcode = nil if barcode.blank?
    self.ipn = nil if ipn.blank?
  end

  # Stamp the internal part number from the organization's IPN engine. In
  # `manual` mode the operator types the reference (or leaves it blank), so we
  # never auto-generate; an explicitly supplied `ipn` in any mode is also left
  # as-is. Otherwise we draw the next reference from the org config and advance
  # its shared counter.
  #
  # A drawn reference can already be taken — a random-mode collision, or a
  # counter the operator manually rewound over existing numbers — so we redraw
  # from the next seed until we find a free one (bounded, so a misconfiguration
  # can't spin forever). This is the "collision triggers a fresh draw" behavior
  # the settings UI promises.
  #
  # The whole thing runs under a row lock so concurrent part creations in the
  # same org can't consume the same sequence number, and it sits in the create
  # transaction so a failed insert rolls the counter advance back too.
  def assign_ipn
    return if ipn.present? || organization.nil?
    return if %w[manual box_bag].include?(organization.ipn_generation_mode)

    organization.with_lock do
      sequence = organization.ipn_next_sequence
      candidate = organization.next_ipn(category_code: category&.code, sequence: sequence)

      attempts = 0
      while organization.parts.exists?(ipn: candidate) && attempts < 100
        sequence += 1
        candidate = organization.next_ipn(category_code: category&.code, sequence: sequence)
        attempts += 1
      end

      self.ipn = candidate
      organization.update_column(:ipn_next_sequence, sequence + 1)
    end
  end

  # In box & bag mode a new part with no IPN of its own takes the first free
  # bag (none free: the part is created without one). Whenever the bag
  # changes, the IPN follows its code, and a previous occupant that emptied the
  # bag gives it up (its leftover empty stock row in the bag is dropped).
  #
  # Runs under the organization's row lock so two parts created at once can't
  # draw the same free bag.
  def claim_bag
    return if organization.nil?

    auto = new_record? && bag_id.nil? && ipn.blank? && organization.ipn_generation_mode == "box_bag"
    return unless auto || will_save_change_to_bag_id?

    organization.with_lock do
      if auto
        taken_ipns = organization.parts.where.not(ipn: nil).pluck(:ipn).map(&:downcase).to_set
        self.bag = organization.free_bags.find { |candidate| taken_ipns.exclude?(candidate.code.to_s.downcase) || candidate.bag_occupant }
      end
      next unless will_save_change_to_bag_id?

      if bag
        previous = organization.parts.where(bag_id: bag_id).where.not(id: id).first
        if previous
          PartStorage.where(part: previous, storage_location: bag, quantity: 0).delete_all
          previous.release_bag!
        end
        self.ipn = bag.code
        self.bag_assigned_at = Time.current
      else
        old_code = StorageLocation.where(id: bag_id_in_database).pick(:code)
        self.ipn = nil if old_code && ipn.to_s.casecmp?(old_code)
        self.bag_assigned_at = nil
      end
    end
  end

  def bag_must_be_free
    if bag.nil? || bag.organization_id != organization_id || !bag.bag?
      errors.add(:bag, "must be a bag of this organization")
    elsif organization && !organization.free_bags(for_part: self).exists?(id: bag.id)
      errors.add(:bag, "#{bag.code} is already holding another part")
    elsif organization.parts.where("LOWER(ipn) = ?", bag.code.to_s.downcase).where.not(id: id).where.not(bag_id: bag.id).exists?
      errors.add(:bag, "#{bag.code} is already another part's IPN")
    end
  end

  def image_source_url_must_be_supplier_image
    return if image_source_url.blank? || image_source_url == self.class.supplier_image_url(image_source_url)

    errors.add(:image_source_url, "must be an https image from a supplier catalog (#{Makerstorage::SUPPLIER_IMAGE_HOSTS.to_sentence})")
  end

  def category_must_belong_to_same_organization
    if category.present? && category.organization_id != organization_id
      errors.add(:category, "must belong to the same organization")
    end
  end

  def footprint_must_belong_to_same_organization
    if footprint.present? && footprint.organization_id != organization_id
      errors.add(:footprint, "must belong to the same organization")
    end
  end
end

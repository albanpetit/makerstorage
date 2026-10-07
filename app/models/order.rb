class Order < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :supplier
  has_many :order_lines, dependent: :destroy
  has_many :parts, through: :order_lines

  # Constants
  STATUSES = %w[pending shipped received cancelled].freeze
  # Forward-only lifecycle an order steps through via #advance!. "cancelled" sits
  # outside this line — it's set directly, not stepped into.
  ADVANCE_SEQUENCE = %w[pending shipped received].freeze

  # Outcome of #advance!: whether it moved, the status it landed on, and any line
  # references that couldn't be credited to stock on receipt.
  AdvanceResult = Struct.new(:advanced, :status, :skipped, keyword_init: true)

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true
  validate :supplier_must_belong_to_same_organization
  validate :status_transition_must_be_allowed, on: :update, if: :status_changed?

  # Scopes
  scope :recent, -> { order(ordered_at: :desc) }
  scope :of_status, ->(status) { where(status: status) }
  scope :pending, -> { where(status: "pending") }
  scope :received, -> { where(status: "received") }

  # Builds a human-readable, per-organization-unique reference of the form
  # "PO-YYYYMMDD-<supplier>" for a supplier's order on a given day. A second
  # order for the same supplier on the same day would otherwise reuse the exact
  # string, so we append "-2", "-3", ... until we find one that's free within
  # the organization.
  def self.next_reference(organization, supplier, date: Date.current)
    base = "PO-#{date.strftime('%Y%m%d')}-#{supplier.id}"
    reference = base
    suffix = 1
    while organization.orders.exists?(reference: reference)
      suffix += 1
      reference = "#{base}-#{suffix}"
    end
    reference
  end

  # Methods
  def pending?
    status == "pending"
  end

  def shipped?
    status == "shipped"
  end

  def received?
    status == "received"
  end

  def cancelled?
    status == "cancelled"
  end

  # Lines and metadata may only be changed while the order is still open. Once
  # received (stock credited) or cancelled, it's frozen so edits can't desync the
  # ledger.
  def editable?
    !received? && !cancelled?
  end

  def computed_total
    order_lines.sum("quantity * unit_price")
  end

  # Recompute and persist total_amount from the current lines. Called after any
  # line is added, repriced, or removed so the stored total never drifts.
  def recalculate_total!
    update_column(:total_amount, computed_total)
  end

  # Steps the order one place along ADVANCE_SEQUENCE, crediting stock when it
  # reaches "received". Row-locks and re-reads status inside the transaction so
  # two concurrent advances can't both credit stock (the second blocks, then
  # re-evaluates the already-advanced status). Returns an AdvanceResult; when
  # already at the end, +advanced+ is false. Preload
  # `order_lines: { part: :storage_locations }` to avoid an N+1 on receipt.
  def advance!(user:)
    advanced = false
    next_status = nil
    skipped = []

    with_lock do
      # A cancelled order sits outside the sequence (index nil) and must stay
      # put — falling back to the start would resurrect it and credit stock.
      current_index = ADVANCE_SEQUENCE.index(status)
      next_status = current_index && ADVANCE_SEQUENCE[current_index + 1]
      break unless next_status

      @advancing = true
      update!(status: next_status)
      skipped = receive_into_stock!(user: user) if next_status == "received"
      advanced = true
    end

    AdvanceResult.new(advanced: advanced, status: next_status, skipped: skipped)
  ensure
    @advancing = false
  end

  # Credits each line's received quantity into stock as "in" movements. A line
  # with configured allocations is split across its target zones (one movement
  # per zone); otherwise it falls back to the part's first location for the whole
  # quantity. Lines with neither an allocation nor a location can't be recorded,
  # so their references are collected and returned rather than silently dropped.
  def receive_into_stock!(user:)
    skipped = []

    order_lines.each do |line|
      allocations = line.allocations.to_a

      if allocations.any?
        allocations.each { |allocation| credit_stock(line.part, allocation.storage_location, allocation.quantity, user) }
        next
      end

      location = line.part.storage_locations.first
      unless location
        skipped << line.part.reference
        next
      end

      credit_stock(line.part, location, line.quantity, user)
    end

    skipped
  end

  private

  def credit_stock(part, location, quantity, user)
    organization.stock_movements.create!(
      part: part, storage_location: location, user: user,
      movement_type: "in", quantity_delta: quantity, reason: "Received #{reference}"
    )
  end

  # Received and cancelled are terminal: re-opening a received order would let
  # #advance! credit its stock a second time. "received" itself is only reachable
  # through #advance!, which is what records the stock receipt.
  def status_transition_must_be_allowed
    if status_was.in?(%w[received cancelled])
      errors.add(:status, "can't change once the order is #{status_was}")
    elsif received? && !@advancing
      errors.add(:status, "can only become received by marking the order received")
    end
  end

  def supplier_must_belong_to_same_organization
    if supplier.present? && supplier.organization_id != organization_id
      errors.add(:supplier, "must belong to the same organization")
    end
  end
end

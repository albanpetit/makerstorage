# A stocktake (cycle count) of one storage zone, and by default every zone
# beneath it. Starting one snapshots the stock the ledger holds there as lines;
# people then count what is physically on the shelf (by hand or with the
# scanner), and completing it writes each difference as an `adjustment`
# movement, so the ledger stays the only thing that changes stock.
#
# A line's expected quantity is refreshed each time it is counted: stock that
# moves while a zone is being counted (someone takes a part after its drawer was
# counted) isn't wiped out by the adjustment, which only corrects what the count
# found at that moment.
class Stocktake < ApplicationRecord
  include GeneratedReference

  # Associations
  belongs_to :organization
  belongs_to :storage_location
  belongs_to :user, optional: true
  belongs_to :completed_by, class_name: "User", optional: true
  has_many :stocktake_lines, dependent: :destroy

  # Constants
  STATUSES = %w[in_progress completed].freeze
  # The adjustments a stocktake writes carry this reason (and its reference).
  MOVEMENT_REASON = "Stocktake"
  # A zone is due for a count when no completed stocktake covered it within
  # this many days (the choices the Stocktakes page offers).
  DUE_AFTER_DAYS = [ 30, 90, 180, 365 ].freeze
  DEFAULT_DUE_AFTER_DAYS = 90

  class NotInProgress < StandardError; end

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true
  validates :notes, length: { maximum: 2000 }
  validate :storage_location_must_belong_to_same_organization
  validate :must_not_overlap_another_count, if: :in_progress?

  # Scopes
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :in_progress, -> { where(status: "in_progress") }
  scope :completed, -> { where(status: "completed") }

  # First free "ST-YYYYMMDD-N" reference of the day in the organization (mirrors
  # Project.next_reference).
  def self.next_reference(organization, date: Date.current)
    base = "ST-#{date.strftime('%Y%m%d')}"
    reference = "#{base}-1"
    suffix = 1
    while organization.stocktakes.exists?(reference: reference)
      suffix += 1
      reference = "#{base}-#{suffix}"
    end
    reference
  end

  # Ids of +root_id+ and every zone beneath it, from an organization's zone
  # tree given as parent id => child ids.
  def self.subtree_ids(children_by_parent, root_id)
    ids = []
    queue = [ root_id ]
    while (id = queue.shift)
      next if ids.include?(id)

      ids << id
      queue.concat(children_by_parent.fetch(id, []))
    end
    ids
  end

  def self.children_by_parent(organization)
    organization.storage_locations.pluck(:id, :parent_id).group_by(&:last).transform_values { |rows| rows.map(&:first) }
  end

  # When each zone of the organization was last covered by a completed
  # stocktake, as zone id => time. Zones never counted are absent.
  def self.last_counted_at_by_zone(organization)
    children = children_by_parent(organization)
    organization.stocktakes.completed.pluck(:storage_location_id, :include_sub_zones, :completed_at)
      .each_with_object({}) do |(root_id, sub_zones, at), counted|
        ids = sub_zones ? subtree_ids(children, root_id) : [ root_id ]
        ids.each { |id| counted[id] = at if counted[id].nil? || at > counted[id] }
      end
  end

  # Methods - Status
  def in_progress?
    status == "in_progress"
  end

  def completed?
    status == "completed"
  end

  # Methods - Scope

  # The zones this stocktake counts: its zone, plus every zone beneath it when
  # it includes sub-zones.
  def location_ids
    @location_ids ||= if include_sub_zones && storage_location_id
      self.class.subtree_ids(self.class.children_by_parent(organization), storage_location_id)
    else
      [ storage_location_id ].compact
    end
  end

  def covers?(location)
    location_ids.include?(location.is_a?(StorageLocation) ? location.id : location.to_i)
  end

  # Methods - Counting

  # Creates a line for every part with stock in the counted zones, expecting
  # what the ledger holds there now.
  def snapshot_stock!
    PartStorage.joins(:part)
      .where(storage_location_id: location_ids, parts: { organization_id: organization_id })
      .where.not(quantity: 0)
      .pluck(:part_id, :storage_location_id, :quantity)
      .each do |part_id, location_id, quantity|
        stocktake_lines.create!(part_id: part_id, storage_location_id: location_id, expected_quantity: quantity)
      end
  end

  # The line for +part+ in +location+, created (expecting the current stock)
  # when the part wasn't listed there: a part found where the ledger had none.
  def line_for!(part, location)
    ensure_in_progress!
    stocktake_lines.find_or_create_by!(part: part, storage_location: location) do |line|
      line.expected_quantity = PartStorage.find_by(part: part, storage_location: location)&.quantity || 0
    end
  end

  # Records +quantity+ as counted on +line+ (nil clears the count), and
  # refreshes what the ledger expects there to the stock at this moment.
  def count!(line, quantity, user:)
    ensure_in_progress!
    line.update!(
      counted_quantity: quantity,
      counted_at: (Time.current unless quantity.nil?),
      counted_by: (user unless quantity.nil?),
      expected_quantity: line.current_quantity
    )
  end

  # Writes an adjustment movement for every counted line whose count differs
  # from what the ledger expected, and closes the stocktake. With
  # +zero_uncounted+, lines nobody counted are taken as found empty; otherwise
  # they are left alone. All or nothing: a movement the ledger refuses (an
  # overdraw, a bag held by another part) rolls everything back. Returns the
  # number of adjustments written.
  def complete!(user:, zero_uncounted: false)
    transaction do
      lock!
      ensure_in_progress!

      lines = stocktake_lines.includes(:part, :storage_location).order(:id).to_a
      adjusted = lines.count do |line|
        if line.counted_quantity.nil?
          next false unless zero_uncounted

          line.assign_attributes(counted_quantity: 0, counted_at: Time.current, counted_by: user, expected_quantity: line.current_quantity)
        end

        delta = line.difference
        if delta.nonzero?
          line.stock_movement = organization.stock_movements.create!(
            part: line.part, storage_location: line.storage_location, user: user,
            movement_type: "adjustment", quantity_delta: delta,
            reason: MOVEMENT_REASON, reference: reference
          )
        end
        line.save!
        delta.nonzero?
      end

      update!(status: "completed", completed_at: Time.current, completed_by: user)
      adjusted
    end
  end

  # Methods - Summary
  def counted_lines_count
    stocktake_lines.count { |line| line.counted? }
  end

  def discrepancy_lines_count
    stocktake_lines.count { |line| line.counted? && line.difference.nonzero? }
  end

  private

  def ensure_in_progress!
    raise NotInProgress, I18n.t("errors.stocktakes.already_completed") unless in_progress?
  end

  def storage_location_must_belong_to_same_organization
    if storage_location.present? && storage_location.organization_id != organization_id
      errors.add(:storage_location, :same_organization)
    end
  end

  # Two counts running over the same zone would both adjust it, doubling the
  # correction.
  def must_not_overlap_another_count
    return if organization.nil? || storage_location_id.nil?

    others = organization.stocktakes.in_progress.where.not(id: id).to_a
    return if others.empty?

    mine = location_ids.to_set
    clash = others.find { |other| other.location_ids.any? { |id| mine.include?(id) } }
    if clash
      errors.add(:storage_location, :already_counted, stocktake: clash.reference.presence || I18n.t("errors.stocktakes.another"))
    end
  end
end

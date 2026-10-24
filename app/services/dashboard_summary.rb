# What the dashboard shows for one organization: headline figures, the last
# 30 days of stock activity, what needs attention (low stock, late orders,
# projects short of parts) and the latest movements. Days are counted in the
# organization's time zone, like the email digest (see NotificationDigest).
class DashboardSummary
  ACTIVITY_DAYS = 30
  LOW_STOCK_LIMIT = 8
  OPEN_ORDERS_LIMIT = 5
  PROJECTS_LIMIT = 5
  TOP_CONSUMED_LIMIT = 5
  CATEGORIES_LIMIT = 6
  RECENT_MOVEMENTS_LIMIT = 8

  attr_reader :organization, :today

  def initialize(organization, now: Time.current)
    @organization = organization
    @now = now
    @today = organization.local_date(now)
  end

  def as_props
    {
      stats: stats,
      activity: activity,
      attention: attention,
      category_breakdown: category_breakdown,
      low_stock_parts: low_stock_parts,
      open_orders: open_orders,
      projects: projects,
      top_consumed: top_consumed,
      recent_movements: recent_movements,
      getting_started: getting_started
    }
  end

  def stats
    {
      references_count: organization.total_parts_count,
      new_references_count: organization.parts.where(created_at: activity_start..).count,
      total_units: organization.total_stock_units,
      stock_value: organization.total_stock_value.to_f,
      alerts_count: organization.low_stock_parts_count,
      out_of_stock_count: organization.out_of_stock_parts_count,
      open_orders_count: open_orders_scope.count,
      late_orders_count: late_orders_scope.count,
      incoming_value: OrderLine.joins(:order).merge(open_orders_scope).sum("order_lines.quantity * COALESCE(order_lines.unit_price, 0)").to_f,
      projects_count: organization.projects.count,
      currency: organization.currency
    }
  end

  # One entry per day, oldest first, counting movements by type.
  def activity
    counts = organization.stock_movements.where(created_at: activity_start..)
      .pluck(:created_at, :movement_type)
      .each_with_object(Hash.new { |hash, day| hash[day] = Hash.new(0) }) do |(created_at, type), by_day|
        by_day[created_at.in_time_zone(organization.timezone).to_date][type] += 1
      end

    ((today - (ACTIVITY_DAYS - 1))..today).map do |day|
      { date: day.iso8601, in: counts[day]["in"], out: counts[day]["out"], adjustment: counts[day]["adjustment"] }
    end
  end

  # Short to-do list: only the items that currently apply.
  def attention
    items = []
    late = late_orders_scope.count
    items << { kind: "late_orders", count: late, href: "/orders" } if late.positive?
    shipped = organization.orders.where(status: "shipped").count
    items << { kind: "shipped_orders", count: shipped, href: "/orders" } if shipped.positive?
    out_of_stock = organization.out_of_stock_parts_count
    items << { kind: "out_of_stock", count: out_of_stock, href: "/alerts" } if out_of_stock.positive?
    low = organization.low_stock_parts_count - out_of_stock
    items << { kind: "low_stock", count: low, href: "/alerts" } if low.positive?
    short = confirmed_projects.count { |project| !project.buildable? }
    items << { kind: "projects_short", count: short, href: "/projects" } if short.positive?
    items
  end

  # Biggest categories by number of references; the rest folds into "Other".
  def category_breakdown
    counts = organization.parts.joins(:category).group("categories.name").count.sort_by { |name, count| [ -count, name ] }
    top = counts.first(CATEGORIES_LIMIT)
    rest = counts.drop(CATEGORIES_LIMIT).sum { |_, count| count }
    top << [ "Other", rest ] if rest.positive?
    total = counts.sum { |_, count| count }
    top.map { |name, count| { name: name, count: count, pct: (count * 100.0 / total).round } }
  end

  # Parts under their threshold, most critical first, with what's already on
  # open orders so nobody reorders them twice.
  def low_stock_parts
    parts = organization.parts.low_stock.includes(:part_storages, :storage_locations)
      .sort_by { |part| [ part.total_quantity.to_f / part.min_stock_threshold, part.name ] }
      .first(LOW_STOCK_LIMIT)
    incoming = Order.incoming_quantities(organization, parts.map(&:id))

    parts.map do |part|
      {
        id: part.id,
        reference: part.reference,
        name: part.name,
        location_name: part.storage_locations.first&.name,
        quantity: part.total_quantity,
        min_stock_threshold: part.min_stock_threshold,
        incoming: incoming[part.id].to_i
      }
    end
  end

  # Pending and shipped orders, late ones first, then by expected delivery.
  def open_orders
    open_orders_scope.includes(:supplier).left_joins(:order_lines).group("orders.id")
      .select("orders.*, COUNT(order_lines.id) AS lines_count")
      .order(Arel.sql("orders.expected_delivery IS NULL, orders.expected_delivery, orders.id"))
      .limit(OPEN_ORDERS_LIMIT)
      .map do |order|
        late = order.expected_delivery && order.expected_delivery < today
        {
          id: order.id,
          reference: order.reference,
          supplier_name: order.supplier.name,
          status: order.status,
          expected_delivery: order.expected_delivery&.iso8601,
          days_late: late ? (today - order.expected_delivery).to_i : 0,
          lines_count: order.lines_count.to_i,
          total_amount: order.total_amount.to_f
        }
      end
  end

  # Latest projects with whether they can be built from stock right now.
  def projects
    recent_projects.map do |project|
      {
        id: project.id,
        name: project.name,
        reference: project.reference,
        status: project.status,
        reserved: project.reserving?,
        lines_count: project.project_lines.size,
        buildable: project.buildable?,
        short_count: project.short_lines.size + project.unmatched_lines.size,
        builds_count: project.builds_count,
        last_built_at: project.last_built_at&.iso8601
      }
    end
  end

  # Parts that left stock the most over the activity window (outbound units).
  def top_consumed
    rows = organization.stock_movements.outbound.where(created_at: activity_start..)
      .group(:part_id).order(Arel.sql("SUM(quantity_delta)")).limit(TOP_CONSUMED_LIMIT)
      .pluck(:part_id, Arel.sql("-SUM(quantity_delta)"))
    parts = organization.parts.where(id: rows.map(&:first)).index_by(&:id)

    rows.map do |part_id, units|
      part = parts[part_id]
      { id: part_id, reference: part.reference, name: part.name, units: units.to_i }
    end
  end

  def recent_movements
    organization.stock_movements
      .includes(:part, :storage_location, :user)
      .recent
      .limit(RECENT_MOVEMENTS_LIMIT)
      .map do |movement|
        {
          id: movement.id,
          part_id: movement.part_id,
          reference: movement.part.reference,
          part_name: movement.part.name,
          location_name: movement.storage_location.name,
          movement_type: movement.movement_type,
          quantity_delta: movement.quantity_delta,
          reason: movement.reason,
          user_name: movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil,
          created_at: movement.created_at.iso8601
        }
      end
  end

  # First steps for a new organization; nil once it has parts in stock.
  def getting_started
    return nil if organization.stock_movements.exists?

    {
      zone: organization.storage_locations.exists?,
      supplier: organization.suppliers.where(catalog_provider: nil).exists?,
      part: organization.parts.exists?,
      movement: false
    }
  end

  private

  def activity_start
    (today - (ACTIVITY_DAYS - 1)).in_time_zone(organization.timezone).beginning_of_day
  end

  def open_orders_scope
    organization.orders.where(status: Order::OPEN_STATUSES)
  end

  def late_orders_scope
    open_orders_scope.where(expected_delivery: ...today)
  end

  def recent_projects
    @recent_projects ||= organization.projects.recent.limit(PROJECTS_LIMIT)
      .includes(project_lines: { part: :part_storages }).to_a.each { |project| project.structure = project_structure }
  end

  def confirmed_projects
    @confirmed_projects ||= organization.projects.where(status: "confirmed")
      .includes(project_lines: { part: :part_storages }).to_a.each { |project| project.structure = project_structure }
  end

  # Shared by the projects above, so sub-assemblies and reservations are read once.
  def project_structure
    @project_structure ||= ProjectStructure.new(organization)
  end
end

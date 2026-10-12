# The alerts an organization's email digest reports (see NotificationDigestJob
# and NotificationMailer#digest): parts below their low-stock threshold and open
# purchase orders past their expected delivery date. Each section only appears
# when its switch is on in Settings → Notifications.
class NotificationDigest
  # Rows listed per section; the email links to the app for the rest.
  LIMIT = 50

  LowStockItem = Data.define(:part_id, :code, :name, :quantity, :threshold)
  LateOrderItem = Data.define(:order_id, :reference, :supplier_name, :expected_delivery, :days_late)

  attr_reader :organization, :date

  # Whether this install can send mail at all (no SMTP in production = no).
  def self.available?
    Rails.configuration.x.email_notifications != false
  end

  def initialize(organization, date: organization.local_date)
    @organization = organization
    @date = date
  end

  def low_stock
    return [] unless organization.notify_low_stock

    @low_stock ||= organization.parts.low_stock
      .select("parts.id, parts.ipn, parts.mpn, parts.name, parts.min_stock_threshold, COALESCE(SUM(part_storages.quantity), 0) AS stock_quantity")
      .order(Arel.sql("COALESCE(SUM(part_storages.quantity), 0) * 1.0 / NULLIF(parts.min_stock_threshold, 0)"), :name)
      .map do |part|
        LowStockItem.new(part_id: part.id, code: part.ipn.presence || part.mpn, name: part.name,
                         quantity: part.stock_quantity.to_i, threshold: part.min_stock_threshold)
      end
  end

  def late_orders
    return [] unless organization.notify_late_orders

    @late_orders ||= organization.orders
      .where(status: Order::OPEN_STATUSES)
      .where(expected_delivery: ...date)
      .includes(:supplier)
      .order(:expected_delivery, :id)
      .map do |order|
        LateOrderItem.new(order_id: order.id, reference: order.reference, supplier_name: order.supplier.name,
                          expected_delivery: order.expected_delivery, days_late: (date - order.expected_delivery).to_i)
      end
  end

  def empty?
    low_stock.empty? && late_orders.empty?
  end
end

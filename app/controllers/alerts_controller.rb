# frozen_string_literal: true

class AlertsController < ApplicationController
  include Auth

  before_action :verify_organization_access

  ORDER_STATUS_SEQUENCE = %w[pending shipped received].freeze

  def index
    render inertia: "alerts/index", props: {
      alerts: compute_alerts.map { |alert| serialize_alert(alert) },
      orders: current_organization.purchases
        .where(status: %w[pending shipped])
        .includes(:supplier, :purchase_lines)
        .order(created_at: :desc)
        .map { |purchase| serialize_order(purchase) }
    }
  end

  def create_purchase_orders
    alerts = compute_alerts.select { |alert| alert[:part].preferred_supplier.present? }
    alerts = alerts.select { |alert| alert[:part].id == params[:part_id].to_i } if params[:part_id].present?

    if alerts.empty?
      redirect_to alerts_path, alert: "No alert has a preferred supplier to order from."
      return
    end

    grouped = alerts.group_by { |alert| alert[:part].preferred_supplier }
    created = 0

    grouped.each do |supplier, supplier_alerts|
      total = supplier_alerts.sum { |alert| alert[:reorder_quantity] * alert[:unit_price] }

      purchase = current_organization.purchases.create!(
        supplier: supplier,
        status: "pending",
        ordered_at: Date.current,
        reference: "PO-#{Date.current.strftime('%Y%m%d')}-#{supplier.id}",
        total_amount: total
      )

      supplier_alerts.each do |alert|
        PurchaseLine.create!(
          purchase: purchase, part: alert[:part],
          quantity: alert[:reorder_quantity], unit_price: alert[:unit_price]
        )
      end

      created += 1
    end

    redirect_to alerts_path, notice: "Created #{created} purchase order#{'s' if created != 1} for #{grouped.values.flatten.size} reference#{'s' if grouped.values.flatten.size != 1}."
  end

  def advance_order
    purchase = current_organization.purchases.find(params[:id])
    current_index = ORDER_STATUS_SEQUENCE.index(purchase.status) || 0
    next_status = ORDER_STATUS_SEQUENCE[current_index + 1]

    unless next_status
      redirect_to alerts_path, alert: "This order has already been received."
      return
    end

    purchase.update!(status: next_status)
    receive_stock(purchase) if next_status == "received"

    redirect_to alerts_path, notice: "Order #{purchase.reference} marked as #{next_status}."
  end

  private

  def compute_alerts
    current_organization.parts.low_stock.includes(:category, :storage_locations, part_suppliers: :supplier).map do |part|
      quantity = part.total_quantity
      threshold = part.min_stock_threshold
      target = part.target_stock || threshold * 2
      preferred = part.preferred_part_supplier

      {
        part: part,
        quantity: quantity,
        threshold: threshold,
        ratio: threshold.positive? ? (quantity.to_f / threshold * 100).round : 0,
        severity: quantity <= threshold * 0.6 ? "critical" : "low",
        reorder_quantity: [ target - quantity, threshold ].max,
        unit_price: (preferred&.unit_price || part.unit_price || 0).to_f
      }
    end.sort_by { |alert| alert[:ratio] }
  end

  def serialize_alert(alert)
    part = alert[:part]

    {
      id: part.id,
      reference: part.mpn.presence || part.sku.presence || part.name,
      name: part.name,
      category: part.category ? { name: part.category.name, color: part.category.color } : nil,
      location_name: part.storage_locations.first&.name,
      quantity: alert[:quantity],
      min_stock_threshold: alert[:threshold],
      severity: alert[:severity],
      supplier_name: part.preferred_supplier&.name,
      unit_price: alert[:unit_price],
      reorder_quantity: alert[:reorder_quantity]
    }
  end

  def serialize_order(purchase)
    {
      id: purchase.id,
      reference: purchase.reference,
      supplier_name: purchase.supplier.name,
      ordered_at: purchase.ordered_at&.iso8601,
      status: purchase.status,
      total_amount: (purchase.total_amount || purchase.computed_total).to_f,
      line_count: purchase.purchase_lines.size
    }
  end

  def receive_stock(purchase)
    purchase.purchase_lines.each do |line|
      location = line.part.storage_locations.first
      next unless location

      StockMovement.create!(
        organization: current_organization, part: line.part, storage_location: location, user: current_user,
        movement_type: "in", quantity_delta: line.quantity, reason: "Received #{purchase.reference}"
      )
    end
  end
end

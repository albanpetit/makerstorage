# frozen_string_literal: true

class AlertsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create_purchase_orders advance_order]

  def index
    render inertia: "alerts/index", props: {
      alerts: compute_alerts.map { |alert| serialize_alert(alert) },
      orders: current_organization.orders
        .where(status: %w[pending shipped])
        .includes(:supplier, :order_lines)
        .order(created_at: :desc)
        .map { |order| serialize_order(order) }
    }
  end

  def create_purchase_orders
    alerts = compute_alerts.select { |alert| alert[:preferred_supplier].present? }
    alerts = alerts.select { |alert| alert[:part].id == params[:part_id].to_i } if params[:part_id].present?

    if alerts.empty?
      redirect_to alerts_path, alert: "No alert has a preferred supplier to order from."
      return
    end

    grouped = alerts.group_by { |alert| alert[:preferred_supplier] }
    created = 0

    # All or nothing: a failure on one supplier mustn't leave the others' orders
    # behind, or a retry would duplicate them.
    ActiveRecord::Base.transaction do
      grouped.each do |supplier, supplier_alerts|
        total = supplier_alerts.sum { |alert| alert[:reorder_quantity] * alert[:unit_price] }

        order = current_organization.orders.new(
          supplier: supplier, status: "pending", ordered_at: Date.current, total_amount: total
        )
        order.save_with_generated_reference! { Order.next_reference(current_organization, supplier) }

        supplier_alerts.each do |alert|
          OrderLine.create!(
            order: order, part: alert[:part],
            quantity: alert[:reorder_quantity], unit_price: alert[:unit_price]
          )
        end

        created += 1
      end
    end

    redirect_to alerts_path, notice: "Created #{created} purchase order#{'s' if created != 1} for #{grouped.values.flatten.size} reference#{'s' if grouped.values.flatten.size != 1}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to alerts_path, alert: "No purchase order was created: #{e.record.errors.full_messages.to_sentence}."
  end

  def advance_order
    # Preload each line's part and its storage locations so Order#advance!'s stock
    # receipt reads `line.part.storage_locations.first` off memory instead of
    # firing a query per line (N+1) once the order is marked received.
    order = current_organization.orders
      .includes(order_lines: [ { part: :storage_locations }, { allocations: :storage_location } ])
      .find(params[:id])

    result = order.advance!(user: current_user)

    unless result.advanced
      redirect_to alerts_path, alert: "This order is already received or cancelled."
      return
    end

    if result.skipped.any?
      redirect_to alerts_path,
        notice: "Order #{order.reference} marked as received.",
        alert: "No stock was recorded for #{result.skipped.to_sentence} — #{result.skipped.one? ? 'it has' : 'they have'} no storage location. Add a location and record the movement manually."
      return
    end

    redirect_to alerts_path, notice: "Order #{order.reference} marked as #{result.status}."
  end

  private

  def compute_alerts
    parts = current_organization.parts.low_stock
      .includes(:category, :part_storages, :storage_locations, part_suppliers: :supplier)

    parts.map do |part|
      # Compute from the preloaded associations rather than `part.total_quantity`
      # /`part.preferred_part_supplier`, which each fire a fresh query per part
      # and turn this into an N+1 across every low-stock alert.
      quantity = part.part_storages.to_a.sum(&:quantity)
      threshold = part.min_stock_threshold
      target = part.target_stock || threshold * 2
      preferred = part.part_suppliers.find(&:is_preferred)

      {
        part: part,
        preferred_supplier: preferred&.supplier,
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
      reference: part.reference,
      name: part.name,
      category: part.category ? { name: part.category.name, color: part.category.color } : nil,
      location_name: part.storage_locations.first&.name,
      quantity: alert[:quantity],
      min_stock_threshold: alert[:threshold],
      severity: alert[:severity],
      supplier_name: alert[:preferred_supplier]&.name,
      unit_price: alert[:unit_price],
      reorder_quantity: alert[:reorder_quantity]
    }
  end

  def serialize_order(order)
    {
      id: order.id,
      reference: order.reference,
      supplier_name: order.supplier.name,
      ordered_at: order.ordered_at&.iso8601,
      status: order.status,
      total_amount: (order.total_amount || order.computed_total).to_f,
      line_count: order.order_lines.size
    }
  end
end

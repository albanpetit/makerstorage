# frozen_string_literal: true

class AlertsController < ApplicationController
  include Auth

  before_action :switch_to_linked_organization, only: :index
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
      redirect_to alerts_path, alert: t("flash.alerts.no_alert_has_a_preferred_supplier")
      return
    end

    # Order only what isn't already on an open order.
    incoming = Order.incoming_quantities(current_organization, alerts.map { |alert| alert[:part].id })
    alerts = alerts.filter_map do |alert|
      quantity = Quantity.sum(alert[:reorder_quantity], -incoming.fetch(alert[:part].id, 0))
      next unless quantity.positive?

      # The preferred supplier's price break for what is actually ordered.
      price = alert[:preferred_link].unit_price_for(quantity) || alert[:part].unit_price || 0
      alert.merge(order_quantity: quantity, unit_price: price.to_f)
    end

    if alerts.empty?
      redirect_to alerts_path, alert: t("flash.alerts.these_parts_are_already_covered_by")
      return
    end

    grouped = alerts.group_by { |alert| alert[:preferred_supplier] }
    created = 0

    # All or nothing: a failure on one supplier mustn't leave the others' orders
    # behind, or a retry would duplicate them.
    ActiveRecord::Base.transaction do
      grouped.each do |supplier, supplier_alerts|
        total = supplier_alerts.sum { |alert| alert[:order_quantity] * alert[:unit_price] }

        order = current_organization.orders.new(
          supplier: supplier, status: "pending", ordered_at: Date.current, total_amount: total
        )
        order.save_with_generated_reference! { Order.next_reference(current_organization, supplier) }

        supplier_alerts.each do |alert|
          OrderLine.create!(
            order: order, part: alert[:part],
            quantity: alert[:order_quantity], unit_price: alert[:unit_price]
          )
        end

        created += 1
      end
    end

    redirect_to alerts_path, notice: t("flash.purchase_orders_created", count: created, references: t("flash.references", count: grouped.values.flatten.size))
  rescue ActiveRecord::RecordInvalid => e
    redirect_to alerts_path, alert: t("flash.alerts.no_purchase_order_was_created", errors: e.record.errors.full_messages.to_sentence)
  end

  def advance_order
    order = current_organization.orders.find(params[:id])

    result = order.advance!(user: current_user)

    unless result.advanced
      redirect_to alerts_path, alert: t("flash.alerts.this_order_is_already_received_or")
      return
    end

    if result.skipped.any?
      redirect_to alerts_path,
        notice: t("flash.alerts.order_marked_as_received", reference: order.reference),
        alert: t("flash.orders.no_stock_recorded", count: result.skipped.size, parts: result.skipped.to_sentence)
      return
    end

    redirect_to alerts_path, notice: t("flash.alerts.order_marked_as", reference: order.reference, status: t("order_statuses.#{result.status}"))
  end

  private

  def compute_alerts
    parts = current_organization.parts.low_stock
      .includes(:category, :part_storages, :storage_locations, part_suppliers: :supplier)

    parts.map do |part|
      # Compute from the preloaded associations rather than `part.total_quantity`
      # /`part.preferred_part_supplier`, which each fire a fresh query per part
      # and turn this into an N+1 across every low-stock alert.
      quantity = Quantity.sum(part.part_storages.map(&:quantity))
      threshold = part.min_stock_threshold
      target = part.target_stock || Quantity.normalize(threshold * 2)
      preferred = part.part_suppliers.find(&:is_preferred)
      reorder_quantity = [ Quantity.sum(target, -quantity), threshold ].max

      {
        part: part,
        preferred_supplier: preferred&.supplier,
        preferred_link: preferred,
        quantity: quantity,
        threshold: threshold,
        ratio: threshold.positive? ? (quantity.to_f / threshold * 100).round : 0,
        severity: quantity <= threshold * 0.6 ? "critical" : "low",
        reorder_quantity: reorder_quantity,
        unit_price: (preferred&.unit_price_for(reorder_quantity) || part.unit_price || 0).to_f
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
      unit: part.unit,
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

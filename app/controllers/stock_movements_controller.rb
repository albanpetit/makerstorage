# frozen_string_literal: true

require "csv"

class StockMovementsController < ApplicationController
  include Auth
  include OptionListSerializers
  include CsvText

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create]

  PAGE_SIZE = 25
  MOVEMENT_TYPES = %w[in out adjustment].freeze
  EXPORT_BATCH_SIZE = 500

  def index
    type = filter_type
    scope = filtered_scope(type)
    total = scope.count
    page_count = [ (total.to_f / PAGE_SIZE).ceil, 1 ].max
    page = requested_page(page_count)

    movements = scope
      .includes(:storage_location, :user, part: :category)
      .order(created_at: :desc, id: :desc)
      .offset((page - 1) * PAGE_SIZE)
      .limit(PAGE_SIZE)
      .to_a

    balances = running_balances(movements.map(&:id))

    render inertia: "stock_movements/index", props: {
      movements: movements.map { |movement| serialize_movement(movement, balances[movement.id]) },
      pagination: { page: page, page_count: page_count, total: total, page_size: PAGE_SIZE },
      filter: type || "all",
      stats: movement_stats,
      parts: serialize_parts,
      storage_locations: serialize_storage_locations
    }
  end

  # Full-ledger CSV download. Paginated views only ever hold one page, so the
  # export is a dedicated endpoint covering every movement matching the active
  # type filter (with the same running balance shown in the table). The ledger
  # only grows, so movements are loaded EXPORT_BATCH_SIZE at a time rather than
  # all instantiated at once.
  def export
    csv = +CSV.generate_line([ "Date", "Type", "Reference", "Reason", "Location", "User", "Quantity", "Stock After" ])

    export_balances(filter_type).each_slice(EXPORT_BATCH_SIZE) do |rows|
      movements = current_organization.stock_movements
        .includes(:storage_location, :user, :part)
        .where(id: rows.map(&:first))
        .index_by(&:id)

      rows.each do |id, balance|
        movement = movements.fetch(id)
        csv << CSV.generate_line([
          movement.created_at.iso8601,
          movement.movement_type,
          csv_text(movement.part.reference),
          csv_text(movement.reason),
          csv_text(movement.storage_location.name),
          csv_text(movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil),
          movement.quantity_delta,
          balance
        ])
      end
    end

    send_data csv, filename: "movements-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  def create
    movement = current_organization.stock_movements.build(movement_params)
    movement.user = current_user
    movement.quantity_delta = signed_quantity

    if movement.save
      redirect_back_or_to stock_movements_path, notice: t("flash.stock_movements.movement_recorded_successfully")
    else
      redirect_back_or_to stock_movements_path, alert: t("flash.stock_movements.failed_to_record_movement"), inertia: { errors: inertia_errors(movement, as: :stock_movement) }
    end
  end

  private

  def movement_params
    params.require(:stock_movement).permit(:part_id, :storage_location_id, :movement_type, :reason)
  end

  def filter_type
    params[:type].presence_in(MOVEMENT_TYPES)
  end

  def filtered_scope(type)
    scope = current_organization.stock_movements
    type ? scope.where(movement_type: type) : scope
  end

  def requested_page(page_count)
    [ [ params[:page].to_i, 1 ].max, page_count ].min
  end

  def signed_quantity
    magnitude = params.dig(:stock_movement, :quantity).to_i

    case params.dig(:stock_movement, :movement_type)
    when "out"
      -magnitude
    when "adjustment"
      params.dig(:stock_movement, :direction) == "decrease" ? -magnitude : magnitude
    else
      magnitude
    end
  end

  # Ledger-wide totals shown in the header cards and filter tabs. These are
  # aggregate queries over the whole table (not the current page), so they stay
  # accurate regardless of pagination or the active filter.
  def movement_stats
    scope = current_organization.stock_movements
    counts = scope.group(:movement_type).count
    sums = scope.group(:movement_type).sum(:quantity_delta)

    {
      inbound: sums["in"] || 0,
      outbound: (sums["out"] || 0).abs,
      total: counts.values.sum,
      in_count: counts["in"] || 0,
      out_count: counts["out"] || 0,
      adjustment_count: counts["adjustment"] || 0
    }
  end

  # Running stock level after each movement of the org. The window sum runs
  # over the org's *entire* ledger per (part, location) so the balance reflects
  # all movement types even when the view is filtered or paginated; callers
  # narrow the outer query to the rows they need. Ordering by (created_at, id)
  # makes the cumulative sum deterministic for movements sharing a timestamp.
  RUNNING_BALANCES_SQL = <<~SQL.squish
    SELECT id, balance_after FROM (
      SELECT id, movement_type, created_at,
             SUM(quantity_delta) OVER (
               PARTITION BY part_id, storage_location_id
               ORDER BY created_at, id
             ) AS balance_after
      FROM stock_movements
      WHERE organization_id = :org
    ) AS running
  SQL

  # id => balance_after for the given movement ids.
  def running_balances(ids)
    return {} if ids.empty?

    StockMovement.connection.select_rows(
      StockMovement.sanitize_sql([ "#{RUNNING_BALANCES_SQL} WHERE id IN (:ids)", org: current_organization.id, ids: ids ])
    ).to_h
  end

  # [id, balance_after] for every movement of +type+ (all when nil), newest
  # first: the export's rows, as plain pairs rather than records.
  def export_balances(type)
    sql = RUNNING_BALANCES_SQL.dup
    sql << " WHERE movement_type = :type" if type
    sql << " ORDER BY created_at DESC, id DESC"

    StockMovement.connection.select_rows(
      StockMovement.sanitize_sql([ sql, org: current_organization.id, type: type ])
    )
  end

  def serialize_movement(movement, balance_after)
    part = movement.part
    {
      id: movement.id,
      created_at: movement.created_at.iso8601,
      movement_type: movement.movement_type,
      quantity_delta: movement.quantity_delta,
      reason: movement.reason,
      balance_after: balance_after,
      user_name: movement.user ? "#{movement.user.firstname} #{movement.user.lastname}".strip : nil,
      location_name: movement.storage_location.name,
      part: {
        id: part.id,
        reference: part.reference,
        name: part.name,
        category: part.category ? { name: part.category.name, color: part.category.color } : nil
      }
    }
  end

  def serialize_parts
    current_organization.parts.alphabetical.map do |part|
      { id: part.id, reference: part.reference, name: part.name }
    end
  end
end

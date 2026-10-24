# frozen_string_literal: true

# Consumption tracking: how fast parts are used up, read from the stock ledger,
# and the low-stock threshold that usage suggests.
#
# Consumption is the "out" movements of the last `consumption_window_days`
# (organization setting), less those that only move stock around: zone moves,
# bag changes and duplicate merges (an out + in pair, marked
# `stock_movements.transfer`) and loans (the items come back; write-offs write no movement).
# Builds, scanner and manual outs all count. Adjustments (stocktake
# differences) don't: they correct the count rather than record a use.
#
# The daily rate divides what was used by the days the part has history for
# (from its first movement), between MIN_RATE_DAYS and the window, so a part
# added last week isn't averaged over three months. The suggested threshold
# holds `threshold_cover_days` of that rate, or the supplier's lead time plus
# SAFETY_DAYS when that's longer (preferred supplier link, then the part's own
# lead time). No suggestion below MIN_MOVEMENTS uses in the window: one take
# says little about a rate.
class PartConsumption
  SAFETY_DAYS = 7
  MIN_RATE_DAYS = 14
  MIN_MOVEMENTS = 2
  MONTHS = 6
  MAX_DAYS = 3650

  Entry = Data.define(:part_id, :consumed, :movements, :days, :daily_rate, :cover_days, :suggested_threshold, :last_used_at) do
    def monthly_rate
      daily_rate * 30
    end

    # Days the given stock lasts at this rate (nil when nothing is used).
    def days_left(quantity)
      return nil unless daily_rate.positive?

      (quantity.to_f / daily_rate).floor
    end
  end

  attr_reader :organization, :today

  def initialize(organization, today: organization.local_date)
    @organization = organization
    @today = today
  end

  def window_days
    organization.consumption_window_days
  end

  def since
    (today - window_days).in_time_zone(organization.timezone)
  end

  # The ledger rows that count as consumption (all dates).
  def movements
    scope = organization.stock_movements.outbound
    loan_references = organization.loans.where.not(reference: nil).select(:reference)
    scope = scope.where(reference: nil).or(scope.where.not(reference: loan_references))
    scope.where(transfer: false)
  end

  # { part_id => Entry } for the given parts (ids or relation) that were used in
  # the window. Parts with no use are left out.
  def for_parts(parts)
    part_ids = parts.is_a?(ActiveRecord::Relation) ? parts.pluck(:id) : Array(parts)
    return {} if part_ids.empty?

    rows = movements.where(part_id: part_ids, created_at: since..)
      .group(:part_id)
      .pluck(:part_id, Arel.sql("-SUM(stock_movements.quantity_delta)"), Arel.sql("COUNT(*)"), Arel.sql("MAX(stock_movements.created_at)"))
    return {} if rows.empty?

    used_ids = rows.map(&:first)
    first_movements = organization.stock_movements.where(part_id: used_ids).group(:part_id).minimum(:created_at)
    lead_times = lead_times_for(used_ids)

    rows.to_h do |part_id, consumed, count, last_used_at|
      # SQLite hands MAX() back as text (UTC), not as a time.
      last_used_at = ActiveSupport::TimeZone["UTC"].parse(last_used_at) if last_used_at.is_a?(String)
      [ part_id, entry(part_id, consumed.to_i, count, first_movements[part_id], lead_times[part_id], last_used_at) ]
    end
  end

  def for_part(part)
    for_parts([ part.id ])[part.id]
  end

  # Units used per calendar month (organization time zone), oldest first,
  # current month included.
  def monthly(part, months: MONTHS)
    start = today.beginning_of_month << (months - 1)
    totals = Hash.new(0)
    movements.where(part_id: part.id, created_at: start.in_time_zone(organization.timezone)..)
      .pluck(:created_at, :quantity_delta).each do |created_at, delta|
        totals[created_at.in_time_zone(organization.timezone).to_date.beginning_of_month] -= delta
      end

    (0...months).map do |offset|
      month = start >> offset
      { month: month.strftime("%Y-%m"), quantity: totals[month] }
    end
  end

  private

  def entry(part_id, consumed, count, first_movement_at, lead_time, last_used_at)
    history_days = first_movement_at ? (today - first_movement_at.in_time_zone(organization.timezone).to_date).to_i : window_days
    days = history_days.clamp(MIN_RATE_DAYS, [ window_days, MIN_RATE_DAYS ].max)
    daily_rate = consumed.to_f / days
    cover_days = [ organization.threshold_cover_days, lead_time.to_i + SAFETY_DAYS ].max
    suggested = (daily_rate * cover_days).ceil if count >= MIN_MOVEMENTS && consumed.positive?

    Entry.new(part_id:, consumed:, movements: count, days:, daily_rate:, cover_days:,
              suggested_threshold: suggested, last_used_at: last_used_at&.in_time_zone(organization.timezone))
  end

  # Preferred supplier link's lead time, else the part's own.
  def lead_times_for(part_ids)
    own = organization.parts.where(id: part_ids).where.not(lead_time_days: nil).pluck(:id, :lead_time_days).to_h
    preferred = PartSupplier.where(part_id: part_ids, is_preferred: true).where.not(lead_time_days: nil)
      .pluck(:part_id, :lead_time_days).to_h
    own.merge(preferred)
  end
end

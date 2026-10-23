# frozen_string_literal: true

# Alerts → Suggested thresholds: each part's consumption over the organization's
# window (PartConsumption) and the low-stock threshold it suggests, applied by
# writers one part at a time or in bulk.
class ThresholdSuggestionsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: :apply

  def index
    consumption = PartConsumption.new(current_organization)
    parts = current_organization.parts.where.not(status: "obsolete")
    entries = consumption.for_parts(parts)
    parts = parts.where(id: entries.keys).includes(:category).index_by(&:id)
    quantities = PartStorage.where(part_id: entries.keys).group(:part_id).sum(:quantity)

    rows = entries.values.filter_map do |entry|
      part = parts[entry.part_id]
      serialize_row(part, entry, quantities.fetch(part.id, 0)) if part
    end

    render inertia: "alerts/thresholds", props: {
      rows: rows.sort_by { |row| [ row[:differs] ? 0 : 1, -row[:consumed], row[:name].downcase ] },
      window_days: current_organization.consumption_window_days,
      cover_days: current_organization.threshold_cover_days
    }
  end

  # Sets each picked part's threshold to its suggestion, recomputed here (the
  # page may be stale). Parts without a suggestion are skipped.
  def apply
    part_ids = Array(params[:part_ids]).map(&:to_i).reject(&:zero?).uniq
    parts = current_organization.parts.where(id: part_ids).to_a
    return redirect_back_or_to(threshold_suggestions_path, alert: t("flash.threshold_suggestions.select_a_part")) if parts.empty?

    entries = PartConsumption.new(current_organization).for_parts(parts.map(&:id))
    updated = 0
    ActiveRecord::Base.transaction do
      parts.each do |part|
        suggested = entries[part.id]&.suggested_threshold
        next if suggested.nil? || suggested == part.min_stock_threshold

        part.update!(min_stock_threshold: suggested)
        updated += 1
      end
    end

    redirect_back_or_to threshold_suggestions_path, notice: t("flash.threshold_suggestions.applied", count: updated)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to threshold_suggestions_path, alert: t("flash.threshold_suggestions.not_applied", errors: e.record.errors.full_messages.to_sentence)
  end

  private

  def serialize_row(part, entry, quantity)
    {
      id: part.id,
      reference: part.reference,
      name: part.name,
      ipn: part.ipn,
      category: part.category ? { name: part.category.name, color: part.category.color } : nil,
      quantity: quantity,
      min_stock_threshold: part.min_stock_threshold,
      suggested_threshold: entry.suggested_threshold,
      consumed: entry.consumed,
      movements: entry.movements,
      monthly_rate: entry.monthly_rate.round(1),
      days_left: entry.days_left(quantity),
      cover_days: entry.cover_days,
      last_used_at: entry.last_used_at&.iso8601,
      differs: differs?(part.min_stock_threshold, entry.suggested_threshold)
    }
  end

  # Worth a look: off by at least one unit and 20% of the larger of the two.
  def differs?(current, suggested)
    return false if suggested.nil?

    (suggested - current).abs >= [ 1, 0.2 * [ suggested, current ].max ].max
  end
end

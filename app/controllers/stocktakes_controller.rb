# frozen_string_literal: true

require "csv"

# Stocktakes (cycle counts): count a zone, review what differs from the
# ledger, and write the corrections as adjustment movements. See Stocktake.
class StocktakesController < ApplicationController
  include Auth
  include OptionListSerializers
  include CsvText

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create destroy complete scan]
  before_action :set_stocktake, only: %i[show destroy complete scan export]

  def index
    stocktakes = current_organization.stocktakes.recent.includes(:storage_location, :user, :completed_by, :stocktake_lines).to_a
    path_cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    due_after = params[:due_after].to_i.presence_in(Stocktake::DUE_AFTER_DAYS) || Stocktake::DEFAULT_DUE_AFTER_DAYS

    render inertia: "stocktakes/index", props: {
      stocktakes: stocktakes.map { |stocktake| serialize_stocktake_summary(stocktake, path_cache) },
      due_zones: due_zones(due_after, path_cache),
      due_after: due_after,
      due_after_options: Stocktake::DUE_AFTER_DAYS,
      storage_locations: serialize_storage_locations
    }
  end

  def show
    lines = @stocktake.stocktake_lines.includes(:part, :storage_location, :counted_by, :stock_movement).to_a
    path_cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    zones = current_organization.storage_locations.where(id: @stocktake.location_ids)
    current_zone = zones.find { |zone| zone.id == params[:zone].to_i }

    render inertia: "stocktakes/show", props: {
      stocktake: serialize_stocktake(@stocktake, lines, path_cache),
      lines: lines.sort_by { |line| [ line.storage_location.full_path(cache: path_cache).downcase, line.part.reference.to_s.downcase ] }
                  .map { |line| serialize_line(line, path_cache) },
      zones: zones.map { |zone| serialize_storage_location_option(zone, zone.path_names(cache: path_cache)) }
                  .sort_by { |zone| zone[:name].downcase },
      current_zone_id: current_zone&.id,
      focus_line_id: params[:line].presence&.to_i,
      # Pick-list for adding a part the ledger didn't expect in the zone.
      parts: @stocktake.in_progress? ? current_organization.parts.alphabetical.map { |part| { id: part.id, reference: part.reference, name: part.name } } : [],
      currency: current_organization.currency
    }
  end

  def create
    location = current_organization.storage_locations.find_by(id: stocktake_params[:storage_location_id])
    return redirect_back_or_to(stocktakes_path, alert: "Pick the zone to count.") unless location

    stocktake = current_organization.stocktakes.new(
      storage_location: location,
      include_sub_zones: ActiveModel::Type::Boolean.new.cast(stocktake_params.fetch(:include_sub_zones, true)),
      blind: ActiveModel::Type::Boolean.new.cast(stocktake_params.fetch(:blind, false)),
      notes: stocktake_params[:notes].presence,
      user: current_user
    )

    ActiveRecord::Base.transaction do
      stocktake.save_with_generated_reference! { Stocktake.next_reference(current_organization) }
      stocktake.snapshot_stock!
    end
    redirect_to stocktake_path(stocktake), notice: "Stocktake #{stocktake.reference} started: #{stocktake.stocktake_lines.size} line#{'s' if stocktake.stocktake_lines.size != 1} to count."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to stocktakes_path, alert: "Could not start the stocktake: #{e.record.errors.full_messages.to_sentence}."
  end

  # Only a count still in progress can be discarded: it hasn't touched stock.
  # A completed one stays as the record of the adjustments it wrote.
  def destroy
    unless @stocktake.in_progress?
      redirect_to stocktake_path(@stocktake), alert: "A completed stocktake is kept with the adjustments it made."
      return
    end

    @stocktake.destroy!
    redirect_to stocktakes_path, notice: "Stocktake #{@stocktake.reference} discarded."
  end

  def complete
    adjusted = @stocktake.complete!(user: current_user, zero_uncounted: ActiveModel::Type::Boolean.new.cast(params[:zero_uncounted]))
    redirect_to stocktake_path(@stocktake),
      notice: adjusted.zero? ? "Stocktake completed: stock matched the count." : "Stocktake completed: #{adjusted} adjustment#{'s' if adjusted != 1} recorded."
  rescue Stocktake::NotInProgress => e
    redirect_to stocktake_path(@stocktake), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    record = e.record
    detail = record.is_a?(StockMovement) ? "#{record.part.reference} in #{record.storage_location.name}: " : ""
    redirect_to stocktake_path(@stocktake), alert: "Nothing was adjusted (#{detail}#{record.errors.full_messages.to_sentence}). Recount that line and try again."
  end

  # One code from the scanner (camera, hardware scanner or typed). A zone code
  # makes that zone the one being counted; a part code opens the part's line in
  # that zone (adding it when the ledger had none there) and, with +increment+,
  # counts one more.
  def scan
    code = ScanCode.normalize(params[:code])
    lookup = ScanCode.new(current_organization)
    zone = current_organization.storage_locations.find_by(id: params[:zone])
    zone = nil unless zone && @stocktake.covers?(zone)

    if code.blank?
      redirect_to stocktake_path(@stocktake, zone: zone&.id)
    elsif (part = lookup.part(code))
      scan_part(part, zone)
    elsif (location = lookup.location(code))
      if @stocktake.covers?(location)
        redirect_to stocktake_path(@stocktake, zone: location.id), notice: "Counting #{location.name}."
      else
        redirect_to stocktake_path(@stocktake, zone: zone&.id), alert: "#{location.name} isn't part of this stocktake."
      end
    else
      redirect_to stocktake_path(@stocktake, zone: zone&.id), alert: "No part or zone matches \"#{code.truncate(60)}\"."
    end
  rescue Stocktake::NotInProgress => e
    redirect_to stocktake_path(@stocktake), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to stocktake_path(@stocktake, zone: zone&.id), alert: e.record.errors.full_messages.to_sentence
  end

  # The count report: one row per line, with what the ledger expected, what
  # was counted and the adjustment written.
  def export
    path_cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    lines = @stocktake.stocktake_lines.includes(:part, :storage_location, :counted_by).to_a
      .sort_by { |line| [ line.storage_location.full_path(cache: path_cache).downcase, line.part.reference.to_s.downcase ] }

    csv = +CSV.generate_line([ "Zone", "Part", "IPN", "Name", "Expected", "Counted", "Difference", "Unit price", "Value difference", "Counted by", "Counted at" ])
    lines.each do |line|
      difference = line.difference
      csv << CSV.generate_line([
        csv_text(line.storage_location.full_path(cache: path_cache)),
        csv_text(line.part.reference),
        csv_text(line.part.ipn),
        csv_text(line.part.name),
        line.expected_quantity,
        line.counted_quantity,
        difference,
        line.part.unit_price,
        (difference * line.part.unit_price if difference && line.part.unit_price),
        csv_text(user_name(line.counted_by)),
        line.counted_at&.iso8601
      ])
    end

    send_data csv, filename: "stocktake-#{@stocktake.reference.presence || @stocktake.id}.csv", type: "text/csv"
  end

  private

  def set_stocktake
    @stocktake = current_organization.stocktakes.find(params[:id])
  end

  def stocktake_params
    params.require(:stocktake).permit(:storage_location_id, :include_sub_zones, :blind, :notes)
  end

  def scan_part(part, zone)
    candidates = @stocktake.stocktake_lines.where(part: part).to_a
    line = if zone
      candidates.find { |candidate| candidate.storage_location_id == zone.id } || @stocktake.line_for!(part, zone)
    elsif candidates.size == 1
      candidates.first
    elsif candidates.empty?
      @stocktake.line_for!(part, @stocktake.storage_location)
    end

    unless line
      redirect_to stocktake_path(@stocktake), alert: "#{part.reference} is stocked in several zones of this count: scan or pick the zone first."
      return
    end

    if ActiveModel::Type::Boolean.new.cast(params[:increment])
      @stocktake.count!(line, line.counted_quantity.to_i + 1, user: current_user)
      notice = "#{part.reference}: #{line.counted_quantity} counted."
    end
    redirect_to stocktake_path(@stocktake, zone: zone&.id, line: line.id), notice: notice
  end

  # Zones holding stock that no completed stocktake covered in the last
  # +days+ days, never-counted ones first, then the longest ago.
  def due_zones(days, path_cache)
    counted = Stocktake.last_counted_at_by_zone(current_organization)
    cutoff = days.days.ago
    stocked = PartStorage.joins(:storage_location)
      .where(storage_locations: { organization_id: current_organization.id })
      .where("part_storages.quantity > 0")
      .group(:storage_location_id)
      .pluck(:storage_location_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(part_storages.quantity)"))
    locations = current_organization.storage_locations.where(id: stocked.map(&:first)).index_by(&:id)

    stocked.filter_map do |location_id, parts_count, units|
      last = counted[location_id]
      next if last && last >= cutoff

      location = locations.fetch(location_id)
      {
        id: location.id,
        name: location.full_path(cache: path_cache),
        code: location.code,
        location_type: location.location_type,
        parts_count: parts_count,
        total_quantity: units,
        last_counted_at: last&.iso8601
      }
    end.sort_by { |zone| [ zone[:last_counted_at] ? 1 : 0, zone[:last_counted_at].to_s, zone[:name].downcase ] }
  end

  def user_name(user)
    user && "#{user.firstname} #{user.lastname}".strip.presence || user&.email
  end

  def serialize_stocktake_summary(stocktake, path_cache)
    lines = stocktake.stocktake_lines
    {
      id: stocktake.id,
      reference: stocktake.reference,
      status: stocktake.status,
      zone_name: stocktake.storage_location.full_path(cache: path_cache),
      include_sub_zones: stocktake.include_sub_zones,
      line_count: lines.size,
      counted_count: stocktake.counted_lines_count,
      discrepancy_count: stocktake.discrepancy_lines_count,
      started_by: user_name(stocktake.user),
      created_at: stocktake.created_at.iso8601,
      completed_at: stocktake.completed_at&.iso8601
    }
  end

  def serialize_stocktake(stocktake, lines, path_cache)
    counted = lines.select(&:counted?)
    differences = counted.map(&:difference)
    {
      id: stocktake.id,
      reference: stocktake.reference,
      status: stocktake.status,
      blind: stocktake.blind,
      include_sub_zones: stocktake.include_sub_zones,
      notes: stocktake.notes,
      zone: { id: stocktake.storage_location.id, name: stocktake.storage_location.full_path(cache: path_cache), code: stocktake.storage_location.code },
      started_by: user_name(stocktake.user),
      created_at: stocktake.created_at.iso8601,
      completed_by: user_name(stocktake.completed_by),
      completed_at: stocktake.completed_at&.iso8601,
      line_count: lines.size,
      counted_count: counted.size,
      discrepancy_count: differences.count(&:nonzero?),
      units_found: differences.select(&:positive?).sum,
      units_missing: -differences.select(&:negative?).sum,
      value_difference: counted.sum { |line| line.difference * (line.part.unit_price || 0) }.to_f.round(2),
      adjustment_count: lines.count(&:stock_movement_id)
    }
  end

  # A blind count hides what the ledger expects until the line is counted, so
  # the count isn't steered by the number on screen.
  def serialize_line(line, path_cache)
    hidden = @stocktake.blind && @stocktake.in_progress? && !line.counted?
    {
      id: line.id,
      part: { id: line.part.id, reference: line.part.reference, ipn: line.part.ipn, name: line.part.name, unit_price: line.part.unit_price&.to_f },
      zone: { id: line.storage_location.id, name: line.storage_location.full_path(cache: path_cache), short_name: line.storage_location.name, code: line.storage_location.code },
      expected_quantity: hidden ? nil : line.expected_quantity,
      counted_quantity: line.counted_quantity,
      difference: line.difference,
      counted_at: line.counted_at&.iso8601,
      counted_by: user_name(line.counted_by),
      adjustment: line.stock_movement && { id: line.stock_movement.id, quantity_delta: line.stock_movement.quantity_delta }
    }
  end
end

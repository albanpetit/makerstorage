# frozen_string_literal: true

# Counting a stocktake by hand: enter a line's count, or add a part the
# ledger didn't expect in one of the counted zones.
class StocktakeLinesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_stocktake

  def create
    part = current_organization.parts.find(line_params[:part_id])
    zone = current_organization.storage_locations.find(line_params[:storage_location_id])
    line = @stocktake.line_for!(part, zone)
    @stocktake.count!(line, counted_quantity, user: current_user) if line_params.key?(:counted_quantity) && !counted_quantity.nil?

    redirect_to stocktake_path(@stocktake, zone: zone.id, line: line.id), notice: t("flash.stocktakes.part_added", reference: part.reference)
  rescue Stocktake::NotInProgress => e
    redirect_to stocktake_path(@stocktake), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to stocktake_path(@stocktake), alert: t("flash.stocktakes.could_not_add_part", errors: e.record.errors.full_messages.to_sentence)
  end

  # A blank count clears the line (back to "not counted").
  def update
    line = @stocktake.stocktake_lines.find(params[:id])
    @stocktake.count!(line, counted_quantity, user: current_user)

    redirect_back_or_to stocktake_path(@stocktake)
  rescue Stocktake::NotInProgress => e
    redirect_to stocktake_path(@stocktake), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to stocktake_path(@stocktake), alert: t("flash.stocktakes.could_not_save_count", errors: e.record.errors.full_messages.to_sentence)
  end

  private

  def set_stocktake
    @stocktake = current_organization.stocktakes.find(params[:stocktake_id])
  end

  def line_params
    params.require(:stocktake_line).permit(:part_id, :storage_location_id, :counted_quantity)
  end

  # Nil for a blank entry; anything else that isn't a number is left as typed
  # so the line's validation rejects it (as it does a fraction of a part
  # counted in pieces).
  def counted_quantity
    raw = line_params[:counted_quantity]
    return nil if raw.blank?

    Quantity.parse(raw) || raw
  end
end

# frozen_string_literal: true

# Inventory → Duplicates: the groups of parts PartDuplicates finds, or the parts
# picked in the inventory list (`part_ids[]`), each merged into the one to keep
# (PartMerge) or marked as not duplicates.
class PartDuplicatesController < ApplicationController
  include Auth

  # Groups shown at once: a fresh import can pair hundreds of parts, and each
  # merge reloads the page anyway.
  MAX_GROUPS = 50

  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[merge dismiss]

  def index
    manual_ids = Array(params[:part_ids]).map(&:to_i).reject(&:zero?).uniq
    if manual_ids.any?
      groups = [ PartDuplicates::Group.new(part_ids: manual_ids, certain: false, reasons: []) ]
      total = 1
    else
      found = PartDuplicates.new(current_organization).groups
      groups = found.first(MAX_GROUPS)
      total = found.size
    end

    parts = serialized_parts(groups.flat_map(&:part_ids))
    render inertia: "part_duplicates/index", props: {
      groups: groups.filter_map { |group| serialize_group(group, parts) },
      total_groups: total,
      manual: manual_ids.any?
    }
  end

  def merge
    keep = current_organization.parts.find(params[:keep_id])
    duplicates = current_organization.parts.where(id: Array(params[:part_ids])).where.not(id: keep.id).to_a
    result = PartMerge.new(keep: keep, duplicates: duplicates, user: current_user).merge!

    redirect_to after_merge_path, notice: merge_notice(result)
  rescue PartMerge::Error => e
    redirect_back_or_to part_duplicates_path, alert: e.message, inertia: { errors: { base: e.message } }
  end

  def dismiss
    parts = current_organization.parts.where(id: Array(params[:part_ids])).to_a
    return redirect_back_or_to(part_duplicates_path, alert: t("flash.part_duplicates.pick_two")) if parts.size < 2

    PartDuplicateDismissal.dismiss!(parts)
    redirect_to part_duplicates_path, notice: t("flash.part_duplicates.dismissed", count: parts.size)
  end

  private

  def serialize_group(group, parts)
    members = group.part_ids.filter_map { |id| parts[id] }
    return if members.size < (params[:part_ids].present? ? 1 : 2)

    { key: group.part_ids.join("-"), certain: group.certain, reasons: group.reasons, parts: members,
      suggested_keep_id: suggested_keep(members) }
  end

  # The part with the most history (movements, order and project lines), then
  # the most stock, then the oldest.
  def suggested_keep(members)
    members.max_by { |part| [ part[:movements_count] + part[:order_lines_count] + part[:project_lines_count], part[:total_quantity], -part[:id] ] }[:id]
  end

  def serialized_parts(ids)
    return {} if ids.empty?

    paths = StorageLocation.full_path_cache(current_organization.storage_locations)
    movements = StockMovement.where(part_id: ids).group(:part_id).count
    order_lines = OrderLine.where(part_id: ids).group(:part_id).count
    project_lines = ProjectLine.where(part_id: ids).group(:part_id).count

    current_organization.parts.where(id: ids)
      .includes(:category, :footprint, :bag, part_storages: :storage_location, part_suppliers: :supplier)
      .to_h do |part|
        storages = part.part_storages.select { |storage| storage.quantity.positive? }
        [ part.id, {
          id: part.id,
          name: part.name,
          ipn: part.ipn,
          mpn: part.mpn,
          sku: part.sku,
          manufacturer: part.manufacturer,
          value: part.value,
          unit: part.unit,
          status: part.status,
          category_name: part.category&.name,
          footprint_name: part.footprint&.name,
          total_quantity: part.part_storages.sum(&:quantity),
          locations: storages.map { |storage| { path: storage.storage_location.path_names(cache: paths).join(" › "), quantity: storage.quantity } },
          suppliers: part.part_suppliers.map { |link| [ link.supplier.name, link.supplier_sku ].compact_blank.join(" ") },
          movements_count: movements.fetch(part.id, 0),
          order_lines_count: order_lines.fetch(part.id, 0),
          project_lines_count: project_lines.fetch(part.id, 0),
          created_at: part.created_at.iso8601
        } ]
      end
  end

  # Parts picked in the inventory list go back there; the finder's groups stay
  # on the duplicates page for the next one.
  def after_merge_path
    params[:return_to] == "parts" ? parts_path : part_duplicates_path
  end

  def merge_notice(result)
    moved = {
      stock_rows: result.stock_rows, movements: result.movements,
      order_lines: result.order_lines, project_lines: result.project_lines
    }.filter_map { |label, count| t("flash.part_duplicates.moved_#{label}", count: count) if count.positive? }
    notice = t("flash.part_duplicates.merged", count: result.merged_count, name: result.kept.name)
    moved.any? ? "#{notice} #{t('flash.part_duplicates.moved', items: moved.to_sentence)}" : notice
  end
end

# frozen_string_literal: true

# Writes the counts and bag receipts the Scanner page queued while it had no
# network (app/frontend/lib/offline-scanner), once it's back online. Each scan
# becomes the movement the online page would have written (same reasons, so
# the "Recent scans" feed and the "already received" warning pick them up),
# stamped with the device's id for the scan and the time it was scanned.
#
# Scans are written one by one, in the order given: one the ledger refuses
# (a part deleted since, a count that would take stock below zero…) is
# reported back and doesn't hold up the others. A scan already written (same
# id: the device didn't get the previous answer) is reported as a duplicate,
# never written twice.
class OfflineScanSync
  MAX_OPERATIONS = 500
  KINDS = %w[count receipt].freeze
  OFFLINE_ID = /\A[\w-]{1,64}\z/

  def initialize(organization, user)
    @organization = organization
    @user = user
  end

  # +operations+: hashes with "id", "kind", "part_id", "storage_location_id",
  # "quantity" (a signed delta for a count, the bag's quantity for a receipt),
  # "reference" (receipts) and "scanned_at". Returns one
  # { id:, status: "saved" | "duplicate" | "rejected", error: } per operation.
  def call(operations)
    Array(operations).first(MAX_OPERATIONS).map { |operation| write(operation.to_h.stringify_keys) }
  end

  private

  def write(operation)
    id = operation["id"].to_s
    return result(id, "rejected", I18n.t("errors.offline_scan.invalid")) unless id.match?(OFFLINE_ID) && KINDS.include?(operation["kind"])
    return result(id, "duplicate") if @organization.stock_movements.exists?(offline_uuid: id)

    part = @organization.parts.find_by(id: operation["part_id"])
    location = @organization.storage_locations.find_by(id: operation["storage_location_id"])
    return result(id, "rejected", I18n.t("errors.offline_scan.not_found")) unless part && location

    movement = build_movement(operation, part, location)
    if movement.save
      result(id, "saved")
    else
      result(id, "rejected", movement.errors.full_messages.to_sentence)
    end
  rescue ActiveRecord::RecordNotUnique
    result(id, "duplicate")
  end

  def build_movement(operation, part, location)
    quantity = Quantity.parse(operation["quantity"]) || 0
    receipt = operation["kind"] == "receipt"

    @organization.stock_movements.build(
      part: part,
      storage_location: location,
      user: @user,
      movement_type: (receipt || quantity.positive?) ? "in" : "out",
      quantity_delta: quantity,
      reason: receipt ? ScansController::LABEL_REASON : ScansController::SCANNER_REASON,
      reference: receipt ? operation["reference"].to_s.strip.first(255).presence : nil,
      offline_uuid: operation["id"],
      scanned_at: scanned_at(operation["scanned_at"])
    )
  end

  # The device's clock: kept when it reads as a time that isn't in the future.
  def scanned_at(value)
    time = Time.zone.parse(value.to_s)
    time if time && time <= Time.current
  rescue ArgumentError
    nil
  end

  def result(id, status, error = nil)
    { id: id, status: status, error: error }.compact
  end
end

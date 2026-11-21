# A CSV import of parts (Inventory → Import), run by PartCsvImportJob so a big
# sheet neither holds a web thread nor hits the proxy's timeout. The uploaded
# file waits in tmp/imports/ (#file_path) until the job has read it. The
# inventory page polls the import (PartsController#import_status) and shows its
# outcome once (seen_at).
class PartImport < ApplicationRecord
  STATUSES = %w[queued running done failed].freeze
  # An import is refused above this many rows (about 3 minutes of work).
  MAX_ROWS = 20_000
  # Finished imports are kept this long, then swept when a new one starts.
  KEPT_FOR = 7.days
  # A running import with no progress for this long died with its worker (a
  # deploy, a crash): it's reported as failed rather than polled forever.
  STALLED_AFTER = 15.minutes
  # Imports run one at a time on the server (PartCsvImportJob), so a queued
  # one may wait behind others: it's only given up after this long.
  QUEUED_FOR_AT_MOST = 1.day
  DIRECTORY = Rails.root.join("tmp", "imports")

  belongs_to :organization
  belongs_to :user, optional: true

  has_secure_token :file_token

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :unseen, -> { where(seen_at: nil) }
  scope :unfinished, -> { where(status: %w[queued running]) }

  def file_path
    DIRECTORY.join("#{file_token}.csv").to_s
  end

  def finished?
    status.in?(%w[done failed])
  end

  def give_up_if_stalled!
    return if finished?
    return if updated_at > (status == "running" ? STALLED_AFTER : QUEUED_FOR_AT_MOST).ago

    update!(status: "failed", error: "unexpected")
    FileUtils.rm_f(file_path)
  end

  def as_status_json
    {
      id: id,
      filename: filename,
      status: status,
      total_rows: total_rows,
      processed_rows: processed_rows,
      created: created_count,
      updated: updated_count,
      skipped: skipped_count,
      # What to tell the user once it's over, in their language.
      message: message
    }
  end

  def message
    case status
    when "done"
      I18n.t("flash.parts.import_complete_created_updated_skipped", created: created_count, updated: updated_count, skipped: skipped_count)
    when "failed"
      I18n.t("errors.part_import.#{error}", default: I18n.t("errors.part_import.unexpected"))
    end
  end

  # Old finished imports of +organization+ (and the file of any that never ran).
  def self.sweep(organization)
    organization.part_imports.where(created_at: ...KEPT_FOR.ago).find_each do |import|
      FileUtils.rm_f(import.file_path)
      import.delete
    end
  end
end

# Runs a CSV import of parts (PartImport) off the request: the file waits in
# tmp/imports/ and is deleted once read. Progress is saved every
# PartCsvImport::PROGRESS_EVERY rows for the inventory page to show.
class PartCsvImportJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(part_import)
    return if part_import.finished?

    unless File.exist?(part_import.file_path)
      return part_import.update!(status: "failed", error: "file_missing")
    end

    # Movements and the summary event are signed with the importing user.
    Current.user = part_import.user
    part_import.update!(status: "running")
    result = PartCsvImport.new(part_import.organization, part_import.user).call(part_import.file_path) do |processed, counts|
      part_import.update_columns(processed_rows: processed, created_count: counts.created,
                                 updated_count: counts.updated, skipped_count: counts.skipped, updated_at: Time.current)
    end

    part_import.update!(
      status: "done", processed_rows: result.created + result.updated + result.skipped,
      created_count: result.created, updated_count: result.updated, skipped_count: result.skipped
    )
    if result.created + result.updated > 0
      ActivityEvent.record!(part_import.organization, "import",
        details: { "file" => part_import.filename, "created" => result.created, "updated" => result.updated, "skipped" => result.skipped })
    end
  rescue CSV::MalformedCSVError
    part_import.update!(status: "failed", error: "unreadable")
  rescue StandardError
    part_import.update!(status: "failed", error: "unexpected")
    raise
  ensure
    Current.user = nil
    FileUtils.rm_f(part_import.file_path) if part_import&.finished?
  end
end

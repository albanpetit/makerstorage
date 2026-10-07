class AttachRemotePartAssetsJob < ApplicationJob
  queue_as :default

  # The part may be deleted before the job runs; there's nothing left to attach
  # to, so drop the job instead of parking it in the failed queue.
  discard_on ActiveJob::DeserializationError

  # Downloads a supplier-provided datasheet URL and attaches it to the part.
  # Runs off the request cycle so a slow or unreachable supplier (e.g. a Mouser
  # datasheet host that times out) never stalls part creation/update.
  #
  # (Images aren't downloaded — Mouser's image CDN blocks server-side fetches, so
  # the catalog image is hotlinked from its URL instead; see PartsController.)
  #
  # Best-effort: RemoteFile returns nil on any failure, so a missing datasheet is
  # silently skipped.
  def perform(part, datasheet_url: nil)
    return if datasheet_url.blank? || part.datasheet.attached?

    file = SupplierCatalog::RemoteFile.download(datasheet_url, default_filename: "datasheet")
    part.datasheet.attach(io: file.io, filename: file.filename, content_type: file.content_type) if file
  end
end

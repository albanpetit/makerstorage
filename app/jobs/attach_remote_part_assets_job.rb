class AttachRemotePartAssetsJob < ApplicationJob
  queue_as :default

  # Downloads supplier-provided datasheet/image URLs and attaches them to the
  # part. Runs off the request cycle so a slow or unreachable supplier (e.g. a
  # Mouser datasheet host that times out) never stalls part creation/update.
  #
  # Best-effort: RemoteFile returns nil on any failure, so a missing asset is
  # silently skipped. The part may have been deleted before the job runs.
  def perform(part, datasheet_url: nil, image_url: nil)
    if datasheet_url.present? && !part.datasheet.attached?
      file = SupplierCatalog::RemoteFile.download(datasheet_url, default_filename: "datasheet")
      part.datasheet.attach(io: file.io, filename: file.filename, content_type: file.content_type) if file
    end

    if image_url.present?
      file = SupplierCatalog::RemoteFile.download(image_url, default_filename: "image")
      part.images.attach(io: file.io, filename: file.filename, content_type: file.content_type) if file
    end
  end
end

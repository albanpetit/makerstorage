# Deletes Active Storage blobs that never ended up attached to a record (an
# upload whose form then failed, an attachment replaced mid-request...). Nothing
# references them, so they would otherwise sit in storage/ forever. The grace
# period leaves room for an upload that is still being attached.
class PurgeUnattachedBlobsJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 2.days

  def perform
    ActiveStorage::Blob.unattached.where(created_at: ...GRACE_PERIOD.ago).find_each(&:purge)
  end
end

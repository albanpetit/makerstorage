require "test_helper"

class PurgeUnattachedBlobsJobTest < ActiveJob::TestCase
  def create_blob(created_at:)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("data"), filename: "logo.png", content_type: "image/png", identify: false
    ).tap do |blob|
      blob.update_column(:created_at, created_at)
    end
  end

  test "purges unattached blobs older than the grace period" do
    stale = create_blob(created_at: 3.days.ago)

    PurgeUnattachedBlobsJob.perform_now

    assert_not ActiveStorage::Blob.exists?(stale.id)
  end

  test "keeps recent unattached blobs and attached ones" do
    recent = create_blob(created_at: 1.hour.ago)
    attached = create_blob(created_at: 3.days.ago)
    assert create_user.organizations.first.logo.attach(attached)

    PurgeUnattachedBlobsJob.perform_now

    assert ActiveStorage::Blob.exists?(recent.id)
    assert ActiveStorage::Blob.exists?(attached.id)
  end
end

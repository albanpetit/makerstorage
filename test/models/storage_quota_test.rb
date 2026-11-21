require "test_helper"

class StorageQuotaTest < ActiveSupport::TestCase
  setup do
    @org = create_user.organizations.first
    @part = create_part(organization: @org)
  end

  test "reads the quota from the environment" do
    {
      nil => nil, "" => nil, "0" => nil, "junk" => nil, "1048576" => 1.megabyte,
      "500MB" => 500.megabytes, "2 gb" => 2.gigabytes, "1.5GB" => (1.5 * 1.gigabyte).to_i
    }.each do |value, expected|
      with_env(value) do
        expected ? assert_equal(expected, Makerstorage.storage_quota_from_env, value.inspect) : assert_nil(Makerstorage.storage_quota_from_env, value.inspect)
      end
    end
  end

  test "counts each file of the organization's records once" do
    attach(@part, :images, 100, "a.png", "image/png")
    attach(@org, :logo, 50, "logo.png", "image/png")
    project = create_project(organization: @org)
    attach(project, :kicad_files, 30, "board.kicad_sch", "application/x-kicad")
    copy = create_project(organization: @org)
    copy.kicad_files.attach(project.kicad_files.first.blob)
    copy.save!
    attach(create_part(organization: create_organization), :images, 999, "other.png", "image/png")

    assert_equal 180, AttachmentValidation.storage_used(@org)
  end

  test "refuses files past the quota, before they are stored" do
    with_quota(150) do
      attach(@part, :images, 100, "a.png", "image/png")

      @part.attachments.attach(io: StringIO.new("z" * 60), filename: "big.step", content_type: "application/step")
      assert_not @part.save
      assert_includes @part.errors[:attachments].join, "150 Bytes"
      assert_equal 1, ActiveStorage::Blob.count

      @part.reload.attachments.attach(io: StringIO.new("z" * 50), filename: "ok.step", content_type: "application/step")
      assert @part.save
    end
  end

  test "no quota, no limit" do
    with_quota(nil) do
      attach(@part, :attachments, 10_000, "a.step", "application/step")
      assert_equal 10_000, AttachmentValidation.storage_used(@org)
    end
  end

  private

  def attach(record, name, size, filename, type)
    record.public_send(name).attach(io: StringIO.new("x" * size), filename: filename, content_type: type)
    record.save!
  end

  def with_quota(bytes)
    previous = Rails.configuration.x.organization_storage_quota
    Rails.configuration.x.organization_storage_quota = bytes
    yield
  ensure
    Rails.configuration.x.organization_storage_quota = previous
  end

  def with_env(value)
    previous = ENV["ORGANIZATION_STORAGE_QUOTA"]
    ENV["ORGANIZATION_STORAGE_QUOTA"] = value
    yield
  ensure
    ENV["ORGANIZATION_STORAGE_QUOTA"] = previous
  end
end

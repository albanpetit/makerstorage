require "test_helper"

class AttachRemotePartAssetsJobTest < ActiveJob::TestCase
  def setup
    @org = create_organization
    @part = create_part(organization: @org)
  end

  test "downloads and attaches datasheet and image" do
    pdf = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("%PDF-1.4 fake"), filename: "ds.pdf", content_type: "application/pdf"
    )
    img = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("fake-image-bytes"), filename: "img.png", content_type: "image/png"
    )

    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(url, **) { url.end_with?(".pdf") ? pdf : img }) do
      AttachRemotePartAssetsJob.perform_now(
        @part,
        datasheet_url: "https://www.mouser.com/ds.pdf",
        image_url: "https://www.mouser.com/img.png"
      )
    end

    @part.reload
    assert @part.datasheet.attached?
    assert @part.images.attached?
  end

  test "skips silently when a download fails" do
    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(*, **) { nil }) do
      AttachRemotePartAssetsJob.perform_now(@part, datasheet_url: "https://www.mouser.com/ds.pdf")
    end

    @part.reload
    refute @part.datasheet.attached?
  end

  test "does not overwrite an existing datasheet" do
    @part.datasheet.attach(
      io: StringIO.new("existing"), filename: "existing.pdf", content_type: "application/pdf"
    )

    called = false
    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(*, **) { called = true; nil }) do
      AttachRemotePartAssetsJob.perform_now(@part, datasheet_url: "https://www.mouser.com/ds.pdf")
    end

    refute called, "should not attempt a download when a datasheet is already attached"
    assert_equal "existing.pdf", @part.reload.datasheet.filename.to_s
  end
end

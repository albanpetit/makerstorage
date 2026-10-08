require "test_helper"

# Every Active Storage route is public (direct uploads need only a CSRF token,
# blob links only the URL), so config/routes.rb shadows them all; files are
# served by StoredFilesController instead.
class ActiveStorageRoutesTest < ActionDispatch::IntegrationTest
  BLOB_PARAMS = { blob: { filename: "x.bin", byte_size: 4, checksum: "AAAAAAAAAAAAAAAAAAAAAA==", content_type: "application/octet-stream" } }.freeze

  test "direct uploads are not served to anonymous visitors" do
    assert_no_difference "ActiveStorage::Blob.count" do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :not_found
  end

  test "direct uploads are not served to signed-in users either" do
    sign_in create_user

    assert_no_difference "ActiveStorage::Blob.count" do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :not_found
  end

  test "the disk upload endpoint is closed" do
    put "/rails/active_storage/disk/sometoken", params: "data"
    assert_response :not_found
  end

  test "public blob links are closed" do
    org = create_user.organizations.first
    org.logo.attach(io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png", identify: false)

    get rails_blob_path(org.logo)
    assert_response :not_found

    get rails_storage_proxy_path(org.logo)
    assert_response :not_found
  end
end

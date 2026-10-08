require "test_helper"

# The app never uses Active Storage direct uploads, and the engine serves them
# to anyone with a CSRF token — no sign-in — so config/routes.rb shadows them.
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

  test "attached files are still served" do
    org = create_user.organizations.first
    org.logo.attach(io: StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'/>"), filename: "logo.svg", content_type: "image/svg+xml")

    get rails_blob_path(org.logo)

    assert_response :redirect
  end
end

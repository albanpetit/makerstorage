require "test_helper"

class StoredFilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @org = @owner.organizations.first
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category)
    @part.images.attach(io: StringIO.new("PNGDATA"), filename: "photo.png", content_type: "image/png", identify: false)
    @image = @part.images.first
  end

  def file_path(attachment)
    stored_file_path(attachment.blob.signed_id, attachment.filename.to_s)
  end

  test "a member of the owning organization gets the file" do
    sign_in @owner
    get file_path(@image)

    assert_response :success
    assert_equal "PNGDATA", response.body
    assert_equal "image/png", response.media_type
    assert_match(/private/, response.headers["Cache-Control"])
  end

  test "organization logos are served to its members" do
    @org.logo.attach(io: StringIO.new("LOGO"), filename: "logo.png", content_type: "image/png", identify: false)

    sign_in @owner
    get file_path(@org.logo)

    assert_response :success
    assert_equal "LOGO", response.body
  end

  test "an svg logo is served as an inline image locked down by its own csp" do
    svg = "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>"
    @org.logo.attach(io: StringIO.new(svg), filename: "logo.svg", content_type: "image/svg+xml", identify: false)

    sign_in @owner
    get file_path(@org.logo)

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
    policy = response.headers["Content-Security-Policy"]
    assert_match(/default-src 'none'/, policy)
    assert_match(/sandbox/, policy)
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "a file missing from storage is not found rather than an error" do
    File.delete(@image.blob.service.path_for(@image.blob.key))

    sign_in @owner
    get file_path(@image)

    assert_response :not_found
  end

  test "signed-out visitors are refused" do
    get file_path(@image)
    # A file request isn't navigational, so Devise answers 401 rather than
    # redirecting to the login page.
    assert_response :unauthorized
  end

  test "users outside the organization get nothing" do
    sign_in create_user
    get file_path(@image)

    assert_response :not_found
  end

  test "a removed member loses access to links they kept" do
    member = create_user
    membership = OrganizationMembership.create!(organization: @org, user: member, role: "member")
    path = file_path(@image)

    sign_in member
    get path
    assert_response :success

    membership.destroy!
    get path
    assert_response :not_found
  end

  test "an unaccepted invitee gets nothing" do
    invitee = create_user
    OrganizationMembership.create!(organization: @org, user: invitee, role: "member", invitation_sent_at: Time.current)

    sign_in invitee
    get file_path(@image)

    assert_response :not_found
  end

  test "a tampered signed id is not found" do
    sign_in @owner
    get stored_file_path("not-a-signed-id", "photo.png")

    assert_response :not_found
  end

  test "the parts list links thumbnails through the member-only route" do
    sign_in @owner
    get parts_path

    props = JSON.parse(response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
    thumbnail = props["parts"].find { |part| part["id"] == @part.id }["thumbnail_url"]
    assert_equal file_path(@image), thumbnail
  end
end

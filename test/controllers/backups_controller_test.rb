require "test_helper"

class BackupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @org = @owner.organizations.first
    @org.update!(name: "Fablab Amiens")
    create_part(organization: @org, name: "10k resistor", mpn: "RC0603-10K")
  end

  test "redirects a signed-out visitor to login" do
    get export_backup_path
    assert_redirected_to new_user_session_path

    post import_backup_path
    assert_redirected_to new_user_session_path
  end

  test "export downloads the current organization as a zip archive" do
    sign_in @owner
    get export_backup_path

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/attachment; filename="makerstorage-fablab-amiens-\d{8}-\d{4}\.zip"/, response.headers["Content-Disposition"])

    Zip::File.open_buffer(response.body) do |zip|
      data = JSON.parse(zip.read("data.json"))
      assert_equal "Fablab Amiens", data["organization"]["name"]
      assert_equal [ "RC0603-10K" ], data["tables"]["parts"].map { |row| row["mpn"] }
    end
  end

  test "export streams the archive from a temporary file it removes afterwards" do
    sign_in @owner
    # Other parallel workers export into the same tmp/backups directory, so
    # check this request's own file (named by SecureRandom.uuid) rather than
    # the whole directory.
    uuids = []
    original_uuid = SecureRandom.method(:uuid)
    stub_singleton(SecureRandom, :uuid, -> { original_uuid.call.tap { |uuid| uuids << uuid } }) do
      get export_backup_path
    end

    assert_response :success
    assert_equal response.body.bytesize, response.headers["Content-Length"].to_i
    assert_nil response.headers["ETag"]
    paths = uuids.map { |uuid| Rails.root.join("tmp/backups/#{uuid}.zip") }
    assert_not_empty paths
    assert paths.none?(&:exist?), "the export file should be removed once sent"
  end

  test "export is admin-only" do
    member = create_user
    OrganizationMembership.create!(organization: @org, user: member, role: "member")

    sign_in member
    post switch_organization_path(@org)
    get export_backup_path

    assert_redirected_to root_path
  end

  test "import restores the archive into a new organization the user owns and switches to it" do
    sign_in @owner
    get export_backup_path
    archive = response.body

    importer = create_user
    sign_in importer

    assert_difference -> { Organization.count }, 1 do
      post import_backup_path, params: { file: upload(archive), name: "Fablab copy" }
    end

    restored = Organization.order(:id).last
    assert_redirected_to settings_path
    assert_match "Restored \"Fablab copy\"", flash[:notice]
    assert_equal restored.id, session[:current_organization_id]
    assert importer.owner_of?(restored)
    assert_equal [ "RC0603-10K" ], restored.parts.pluck(:mpn)
    assert_equal 1, @org.parts.count
  end

  test "import without a file asks for one" do
    sign_in @owner

    assert_no_difference -> { Organization.count } do
      post import_backup_path
    end

    assert_redirected_to settings_path
    assert_equal "Please choose a backup file to restore.", flash[:alert]
  end

  test "import of an invalid file explains why and creates nothing" do
    sign_in @owner

    assert_no_difference -> { Organization.count } do
      post import_backup_path, params: { file: upload("not a zip") }
    end

    assert_redirected_to settings_path
    assert_match "Could not restore the backup", flash[:alert]
  end

  test "import needs a confirmed address when addresses are verified" do
    unconfirmed = create_user(confirmed_at: nil)
    sign_in unconfirmed

    assert_no_difference -> { Organization.count } do
      post import_backup_path, params: { file: upload("not a zip") }
    end

    assert_redirected_to settings_path
    assert_match "Confirm your email address", flash[:alert]
  end

  test "import is rate limited per user" do
    sign_in @owner

    BackupsController::IMPORT_RATE_LIMIT.times { post import_backup_path, params: { file: upload("not a zip") } }
    assert_match "Could not restore the backup", flash[:alert]

    post import_backup_path, params: { file: upload("not a zip") }
    assert_redirected_to settings_path
    assert_equal "Too many restores. Please try again later.", flash[:alert]
  end

  private

  def upload(bytes)
    file = Tempfile.new([ "backup", ".zip" ], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/zip", true, original_filename: "backup.zip")
  end
end

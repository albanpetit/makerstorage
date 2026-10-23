require "test_helper"

class PartAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @part = create_part(organization: @org, name: "STM32F103")
  end

  test "adds files of any type and lists them with the datasheet on the part sheet" do
    @part.datasheet.attach(io: StringIO.new("%PDF-1.4 ds"), filename: "stm32.pdf", content_type: "application/pdf")
    sign_in @user

    assert_difference -> { @part.attachments.count } => 2 do
      post part_attachments_path(@part), params: { files: [ upload("body.step", "ISO-10303-21;"), upload("AN2586.pdf", "%PDF-1.4 an") ] },
                                         headers: { "Referer" => parts_url }
    end
    assert_redirected_to parts_url
    assert_equal "Added 2 files.", flash[:notice]

    get part_path(@part), headers: { "Accept" => "application/json" }
    files = response.parsed_body["part"]["files"]
    assert_equal [ [ "stm32.pdf", true ], [ "body.step", false ], [ "AN2586.pdf", false ] ], files.map { |f| [ f["filename"], f["datasheet"] ] }
    assert files.all? { |f| f["url"].start_with?("/files/") }

    get files.second["url"]
    assert_response :success
    assert_equal "ISO-10303-21;", response.body
  end

  test "removes an attached file or the datasheet" do
    @part.attachments.attach(io: StringIO.new("notes"), filename: "notes.txt")
    @part.datasheet.attach(io: StringIO.new("%PDF-1.4 ds"), filename: "ds.pdf", content_type: "application/pdf")
    sign_in @user

    delete part_attachment_path(@part, @part.attachments.first)
    assert_equal "notes.txt removed.", flash[:notice]
    assert_not @part.reload.attachments.attached?

    delete part_attachment_path(@part, @part.datasheet_attachment)
    assert_not @part.reload.datasheet.attached?
  end

  test "refuses an empty upload, too many files and files that are too large" do
    sign_in @user

    post part_attachments_path(@part), params: { files: [] }
    assert_equal "Please choose files to add.", flash[:alert]

    Part::MAX_ATTACHMENTS.times { |i| @part.attachments.attach(io: StringIO.new("f#{i}"), filename: "f#{i}.txt") }
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post part_attachments_path(@part), params: { files: [ upload("one-more.txt", "x") ] }
    end
    assert_equal "A part can hold up to #{Part::MAX_ATTACHMENTS} files.", flash[:alert]

    @part.attachments.purge
    file = Tempfile.new([ "big", ".bin" ], binmode: true)
    file.truncate(50.megabytes + 1)
    big = Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: "big.bin")
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post part_attachments_path(@part), params: { files: [ big ] }
    end
    assert_match(/big.bin is larger than 50 MB/, flash[:alert])
  end

  test "viewers can open files but not add or remove them" do
    @part.attachments.attach(io: StringIO.new("notes"), filename: "notes.txt")
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    assert_no_difference -> { @part.attachments.count } do
      post part_attachments_path(@part), params: { files: [ upload("x.txt", "x") ] }
    end
    assert_no_difference -> { @part.attachments.count } do
      delete part_attachment_path(@part, @part.attachments.first)
    end

    get part_path(@part), headers: { "Accept" => "application/json" }
    get response.parsed_body["part"]["files"].first["url"]
    assert_response :success
  end

  test "another organization's part and files stay out of reach" do
    other_part = create_part(organization: create_organization)
    other_part.attachments.attach(io: StringIO.new("secret"), filename: "secret.txt")
    sign_in @user

    post part_attachments_path(other_part), params: { files: [ upload("x.txt", "x") ] }
    assert_response :not_found
    sign_in @user # a 404 ends the test session
    delete part_attachment_path(other_part, other_part.attachments.first)
    assert_response :not_found
    assert other_part.reload.attachments.attached?

    # Another part's file id doesn't reach through this part either.
    sign_in @user
    delete part_attachment_path(@part, other_part.attachments.first)
    assert_response :not_found
    assert other_part.reload.attachments.attached?
  end

  private

  def upload(filename, content)
    Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", original_filename: filename)
  end
end

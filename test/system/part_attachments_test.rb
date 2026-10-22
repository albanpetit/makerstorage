require "application_system_test_case"

class PartAttachmentsTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @part = create_part(organization: @org, name: "Microcontroller", mpn: "STM32F103C8T6")
    @part.datasheet.attach(io: StringIO.new("%PDF-1.4 ds"), filename: "stm32f103c8.pdf", content_type: "application/pdf")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "files are added, listed with the datasheet and removed from the part sheet" do
    visit parts_path
    click_on "STM32F103C8T6"

    within("[role='dialog']") do
      assert_text "Files"
      assert_text "stm32f103c8.pdf"
      assert_text "Datasheet"

      file = Tempfile.new([ "bluepill", ".step" ])
      file.write("ISO-10303-21;")
      file.close
      find("input[type='file']", visible: :all).attach_file(file.path, make_visible: true)
      assert_text File.basename(file.path), wait: 10
    end
    assert_equal 1, @part.reload.attachments.count

    name = @part.attachments.first.filename.to_s
    find("button[aria-label='Remove #{name}']").click
    within("[role='alertdialog']") { click_on "Remove" }
    within("[role='dialog']") do
      assert_no_text name, wait: 10
      assert_text "stm32f103c8.pdf"
    end
    assert_not @part.reload.attachments.attached?
  end
end

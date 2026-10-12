require "application_system_test_case"

class OrganizationBackupSystemTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(name: "Fablab Amiens")
    create_part(organization: @org, name: "NE555 timer", mpn: "NE555P")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an admin restores a backup into a new organization from Settings" do
    archive = Rails.root.join("tmp", "backup-system-test-#{SecureRandom.hex(4)}.zip")
    File.binwrite(archive, OrganizationBackup::Exporter.new(@org).to_zip)

    visit settings_path
    click_on "Backup"
    assert_link "Download backup", href: "/backup/export"

    find("input[type='file'][accept='.zip,application/zip']", visible: :all).attach_file(archive)
    assert_text File.basename(archive)
    fill_in "Organization name", with: "Fablab copy"
    click_on "Restore into a new organization"

    assert_text "Restored \"Fablab copy\"", wait: 20
    restored = @user.organizations.find_by!(name: "Fablab copy")
    assert_equal [ "NE555P" ], restored.parts.pluck(:mpn)
  ensure
    FileUtils.rm_f(archive) if archive
  end
end

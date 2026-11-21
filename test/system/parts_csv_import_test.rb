require "application_system_test_case"

class PartsCsvImportSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @org = @user.organizations.first

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "the inventory follows a background import to its end, then lists the new parts" do
    csv = Tempfile.new([ "parts", ".csv" ])
    csv.write("Name,Category,MPN\nResistor 10k,Resistors,R-10K\nCeramic 100n,Capacitors,C-100N\n")
    csv.flush

    visit parts_path
    click_on "Import CSV"
    attach_file "file", csv.path, make_visible: true
    click_on "Confirm import"

    assert_text "Importing 2 rows in the background"
    assert_selector "[role=status]", text: /Importing parts.*\.csv/
    assert_text "0 / 2"

    perform_enqueued_jobs

    assert_text "Import complete: 2 created, 0 updated, 0 skipped.", wait: 10
    assert_no_selector "[role=status]", text: /Importing/
    assert_text "Resistor 10k"
    assert_text "Ceramic 100n"
    assert @org.part_imports.sole.seen_at
  end
end

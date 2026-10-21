require "application_system_test_case"

class LabelPrintersTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @drawer = create_storage_location(organization: @org, name: "Drawer A3", location_type: "drawer")
    @part = create_part(organization: @org, name: "NE555 timer", mpn: "NE555P", ipn: "IC-0042")
    PartStorage.create!(part: @part, storage_location: @drawer, quantity: 25)
    @jobs = []

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  # The server runs in this process, so the stub catches what would reach the
  # printer's socket.
  def capturing_jobs(&block)
    stub_singleton(LabelPrinting::Network, :deliver, ->(host, port, data) { @jobs << [ host, port, data ] }, &block)
  end

  # The black dots of a Brother job's raster lines, mirrored back to the label.
  def brother_dots(job, media)
    lines = job.scan(/g\x00Z(.{90})/mn).flatten
    lines.map { |line| line.unpack1("B*")[media.right_offset, media.printable_width].reverse }
  end

  test "an admin adds a Brother printer and prints a part's label on it" do
    visit settings_path(section: "printers")
    assert_selector "h2", text: "Label printers", wait: 10
    click_on "Add printer"
    within("[role='dialog']") do
      fill_in "Name", with: "Workshop QL-820"
      fill_in "IP address or host name", with: "192.168.1.50"
      click_on "Add printer"
    end
    assert_text "Printer \"Workshop QL-820\" added.", wait: 10
    assert_text "Brother QL · 62 × 29 mm · 192.168.1.50:9100"
    printer = @org.label_printers.sole
    assert_equal "62x29", printer.media

    capturing_jobs do
      visit parts_path
      find("button[aria-label='Select #{@part.name}']", wait: 10).click
      click_on "Labels"
      find("#label-format").click
      find("[role='option']", text: "Workshop QL-820 · 62 × 29 mm").click
      within("[role='dialog']") { click_on "Print 1 label" }
      assert_text "Sent 1 label to Workshop QL-820.", wait: 15
    end

    host, port, job = @jobs.sole
    assert_equal [ "192.168.1.50", 9100 ], [ host, port ]
    rows = brother_dots(job, printer.brother_media)
    assert_equal 271, rows.size
    black = rows.sum { |row| row.count("1") }
    assert black > 5_000, "expected a QR code and text, got #{black} black dots"
    # The QR code sits on the left, the text after it.
    assert rows.any? { |row| row[0, 230].include?("1") }
    assert rows.any? { |row| row[260, 436].include?("1") }
  end

  test "a new part's label prints on the remembered printer" do
    @org.label_printers.create!(name: "Zebra GK420", protocol: "zpl", host: "192.168.1.60",
                                width_mm: 50.8, length_mm: 25.4, dpi: 203)
    category = create_category(organization: @org, name: "Timers")

    capturing_jobs do
      visit parts_path
      # Remember the printer in this browser, as the print dialog does.
      find("button[aria-label='Select #{@part.name}']", wait: 10).click
      click_on "Labels"
      find("#label-format").click
      find("[role='option']", text: "Zebra GK420").click
      within("[role='dialog']") { click_on "Cancel" }

      visit parts_path(new: 1)
      within("[role='dialog']") do
        find("input[placeholder='e.g. Resistor 10k 1% 0603']").fill_in(with: "LM358 op-amp")
        find("#part-category").click
      end
      find("[role='option']", text: "Timers").click
      within("[role='dialog']") do
        find("#print-new-part-label").click
        assert_text "on Zebra GK420"
        click_on "Add part"
      end
      assert_text "Sent 1 label to Zebra GK420.", wait: 15
    end

    _host, _port, job = @jobs.sole
    assert job.start_with?("^XA^PW406^LL203^LH0,0^FO0,0^GFA,10353,10353,51,")
    assert_equal 1, Part.where(name: "LM358 op-amp", category: category).count
  end
end

require "application_system_test_case"

# The Scanner page keeps working when the server can't be reached: scans are
# answered from the data kept on the device, counts and bag receipts wait
# there, and they're written once the server answers again.
class OfflineScannerTest < ApplicationSystemTestCase
  # A DigiKey bag label as a keyboard-mode scanner types it (printable
  # stand-ins for the GS/RS/EOT separators).
  LABEL = "[)>{RS}06{GS}P296-1395-5-ND{GS}1PSN74HC595N{GS}1K84512345{GS}Q25{RS}{EOT}"

  setup do
    @user = create_user
    @org = @user.organizations.first
    @drawer = create_storage_location(organization: @org, name: "Drawer A1", location_type: "drawer", code: "DRW-A1")
    @resistor = create_part(organization: @org, name: "Resistor 10k", ipn: "MS-00042")
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "in", quantity_delta: 10)
    @chip = create_part(organization: @org, name: "Shift register", mpn: "SN74HC595N")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  teardown do
    go_online
  end

  test "counts and receives bags offline, then sends them when back online" do
    visit scan_path
    assert_text "Ready to scan offline", wait: 10

    go_offline
    assert_text "Offline: scans are answered from the data on this device"

    look_up "ms-00042"
    assert_text(/scan matched/i)
    assert_text "Resistor 10k"
    3.times { find("button[aria-label='Add one']").click }
    click_on "Save on this device"
    assert_text "Saved on this device."
    assert_text "1 scan waiting to be sent"

    # The stock shown includes what's waiting.
    look_up "MS-00042"
    within(".font-mono.text-2xl") { assert_text "13" }

    look_up "DRW-A1"
    assert_text "Drawer A1"
    assert_text "Resistor 10k"

    look_up LABEL
    assert_text(/bag matched/i)
    assert_text "SN74HC595N"
    click_on "Receive 25 on this device"
    assert_text "Bag saved on this device"
    assert_text "2 scans waiting to be sent"
    assert_equal 10, @resistor.reload.total_quantity
    assert_equal 0, @chip.reload.total_quantity

    go_online
    assert_no_text "waiting to be sent", wait: 20
    assert_text "Scanner ready"

    assert_equal 13, @resistor.reload.total_quantity
    assert_equal 25, @chip.reload.total_quantity
    receipt = @org.stock_movements.find_by!(part: @chip)
    assert_equal "DigiKey 84512345", receipt.reference
    assert_equal ScansController::LABEL_REASON, receipt.reason
    assert receipt.offline_uuid.present?
    assert receipt.scanned_at.present?
  end

  test "a scan the server refuses stays on the device until discarded" do
    visit scan_path
    assert_text "Ready to scan offline", wait: 10

    go_offline
    look_up "MS-00042"
    assert_text "Resistor 10k"
    5.times { find("button[aria-label='Remove one']").click }
    click_on "Save on this device"
    assert_text "1 scan waiting to be sent"

    # Someone else took the stock meanwhile.
    StockMovement.create!(organization: @org, part: @resistor, storage_location: @drawer, movement_type: "out", quantity_delta: -8)

    go_online
    assert_text "Refused:", wait: 20
    assert_equal 2, @resistor.reload.total_quantity

    find("button[aria-label='Discard']").click
    assert_no_text "waiting to be sent"
  end

  test "the scanner page reopens without a network once it was kept" do
    visit scan_path
    assert_text "Ready to scan offline", wait: 10
    # The service worker keeps a copy of the page in the background.
    Timeout.timeout(20) { sleep 0.2 until page.evaluate_async_script("caches.match('/scan').then((r) => arguments[0](!!r))") }

    go_offline
    visit scan_path
    assert_selector "h1", text: "Scanner"
    assert_text "Offline: scans are answered from the data on this device"
    look_up "MS-00042"
    assert_text "Resistor 10k"
  end

  private

  def look_up(code)
    fill_in placeholder: "IPN, barcode, SKU, MPN, or zone code…", with: code
    click_on "Look up code"
  end

  def go_offline
    page.driver.browser.network_conditions = { offline: true, latency: 0, throughput: -1 }
  end

  def go_online
    page.driver.browser.network_conditions = { offline: false, latency: 0, throughput: -1 }
  end
end

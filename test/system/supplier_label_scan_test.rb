require "application_system_test_case"

# Scanning a distributor's bag label: receive it into a known part, or create
# the part from the label and come back to the scanner.
class SupplierLabelScanTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @drawer = create_storage_location(organization: @org, name: "Drawer A1", location_type: "drawer")
    @digikey = Supplier.ensure_catalog_provider(@org, "digikey").first
    create_category(organization: @org, name: "Logic")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "receiving a bag of a known part" do
    part = create_part(organization: @org, mpn: "SN74HC595N")
    StockMovement.create!(organization: @org, part: part, storage_location: @drawer, movement_type: "in", quantity_delta: 5)

    visit scan_path(code: label)
    assert_text(/bag matched/i)
    assert_text "DigiKey label"
    assert_equal "25", find("input[aria-label='Quantity received']").value

    click_on "Receive 25"
    assert_text "Received 25 × SN74HC595N into Drawer A1."
    assert_equal 30, PartStorage.find_by!(part: part, storage_location: @drawer).quantity

    # Scanning the same bag again warns before it's counted twice.
    visit scan_path(code: label)
    assert_text "This bag was already received"
  end

  test "creating the part from an unknown bag" do
    visit scan_path(code: label)
    assert_text(/new part/i)
    click_on "Create part"

    within("[role='dialog']") do
      assert_equal "SN74HC595N", find("input[placeholder='e.g. Resistor 10k 1% 0603']").value
      find("#part-category").click
    end
    find("[role='option']", text: "Logic").click
    within("[role='dialog']") { find("#part-initial-location").click }
    find("[role='option']", text: "Drawer A1").click
    within("[role='dialog']") do
      assert_selector "input[value='25']"
      click_on "Add part"
    end

    assert_text "Part created successfully."
    assert_selector "h1", text: "Scanner"
    part = @org.parts.find_by!(mpn: "SN74HC595N")
    assert_equal 25, part.total_quantity
    assert_equal "296-1395-5-ND", part.part_suppliers.find_by!(supplier: @digikey).supplier_sku
  end

  private

  def label
    gs = SupplierLabel::GS
    rs = SupplierLabel::RS
    "[)>#{rs}06#{gs}P296-1395-5-ND#{gs}1PSN74HC595N#{gs}1K84512345#{gs}Q25#{rs}#{SupplierLabel::EOT}"
  end
end

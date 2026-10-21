require "test_helper"

class SupplierLabelTest < ActiveSupport::TestCase
  GS = SupplierLabel::GS
  RS = SupplierLabel::RS
  EOT = SupplierLabel::EOT

  def ecia(*fields)
    "[)>#{RS}06#{GS}#{fields.join(GS)}#{RS}#{EOT}"
  end

  test "reads a DigiKey bag label" do
    label = SupplierLabel.parse(ecia(
      "P296-1395-5-ND", "1PSN74HC595N", "K", "1K84512345", "10K98765432", "9D2315",
      "1TABC123", "11K1", "4LMY", "Q25", "11ZPICK", "12Z4389236", "13Z112233", "20Z000000000000"
    ))

    assert_equal "digikey", label.provider
    assert_equal "DigiKey", label.provider_name
    assert_equal "SN74HC595N", label.mpn
    assert_equal "296-1395-5-ND", label.supplier_sku
    assert_nil label.customer_part_number
    assert_equal 25, label.quantity
    assert_equal "84512345", label.order_number
    assert_equal "ABC123", label.lot
    assert_equal "2315", label.date_code
    assert_equal "MY", label.country_of_origin
    assert_equal "DigiKey 84512345", label.movement_reference
  end

  test "keeps a DigiKey customer part number apart from the DigiKey part number" do
    label = SupplierLabel.parse(ecia("PMS-00042", "30P296-1395-5-ND", "1PSN74HC595N", "Q10"))

    assert_equal "digikey", label.provider
    assert_equal "MS-00042", label.customer_part_number
    assert_equal "296-1395-5-ND", label.supplier_sku
  end

  test "reads a Mouser bag label, including its stray leading character" do
    label = SupplierLabel.parse(">#{ecia("K2026-10-PO", "14K001", "1PRC0805FR-0710KL", "Q100", "11K12345678", "4LTW", "1VYAGEO")}")

    assert_equal "mouser", label.provider
    assert_equal "RC0805FR-0710KL", label.mpn
    assert_equal "YAGEO", label.manufacturer
    assert_equal 100, label.quantity
    assert_equal "12345678", label.order_number
    assert_nil label.supplier_sku
  end

  test "reads an LCSC QR label" do
    label = SupplierLabel.parse("{pbn:PICK2309150012,on:WM2309150055,pc:C2040,pm:RP2040,qty:10,mc:,cc:1,pdi:93421544,hp:0,wc:ZH}")

    assert_equal "lcsc", label.provider
    assert_equal "RP2040", label.mpn
    assert_equal "C2040", label.supplier_sku
    assert_equal 10, label.quantity
    assert_equal "WM2309150055", label.order_number
  end

  test "accepts the separator stand-ins keyboard-mode scanners type" do
    label = SupplierLabel.parse("[)>{RS}06{GS}1PNE555P{GS}Q5{GS}1K777{RS}{EOT}")

    assert_equal "NE555P", label.mpn
    assert_equal 5, label.quantity
    assert_equal "777", label.order_number
    assert_nil label.provider
    assert_equal "Supplier 777", label.movement_reference
  end

  test "drops an unusable quantity" do
    assert_nil SupplierLabel.parse(ecia("1PNE555P", "Q0")).quantity
    assert_nil SupplierLabel.parse(ecia("1PNE555P", "Q12a")).quantity
    assert_nil SupplierLabel.parse(ecia("1PNE555P", "Q99999999999")).quantity
  end

  test "ignores codes that aren't supplier labels" do
    assert_nil SupplierLabel.parse("MS-00042")
    assert_nil SupplierLabel.parse("zone:12")
    assert_nil SupplierLabel.parse("")
    assert_nil SupplierLabel.parse(nil)
    assert_nil SupplierLabel.parse("{not:lcsc}")
  end

  test "ignores a label with no part number" do
    assert_nil SupplierLabel.parse(ecia("Q10", "1K12345"))
    assert_nil SupplierLabel.parse("[)>06 garbage")
  end
end

require "test_helper"

class BomParserTest < ActiveSupport::TestCase
  test "parses comma-separated rows into normalized hashes" do
    rows = parse(<<~CSV)
      Designation,MPN,SKU,Quantity
      Resistor 10k,RC0805-10K,,10
      Cap 100nF,,CAP100NF,4
    CSV

    assert_equal 2, rows.size
    assert_equal({ designation: "Resistor 10k", mpn: "RC0805-10K", sku: nil, quantity: 10 }, rows.first)
  end

  test "sniffs a semicolon delimiter" do
    rows = parse("Designation;Quantity\nResistor;3\n")
    assert_equal "Resistor", rows.first[:designation]
    assert_equal 3, rows.first[:quantity]
  end

  test "recognizes French BOM-style column synonyms" do
    rows = parse("Désignation;Référence;Quantité\nRésistance;REF-1;7\n")
    assert_equal "Résistance", rows.first[:designation]
    assert_equal "REF-1", rows.first[:sku]
    assert_equal 7, rows.first[:quantity]
  end

  test "reads a Windows-1252 file as saved by Excel on French Windows" do
    content = "Désignation;Référence;Quantité\r\nRésistance 10kΩ €;REF-1;7\r\n".encode("Windows-1252", undef: :replace)
    rows = parse(content.b)

    assert_equal "Résistance 10k? €", rows.first[:designation]
    assert_equal "REF-1", rows.first[:sku]
    assert_equal 7, rows.first[:quantity]
  end

  test "ignores a UTF-8 byte-order mark" do
    rows = parse("\uFEFFDesignation;Quantity\nResistor;3\n")
    assert_equal "Resistor", rows.first[:designation]
  end

  test "quantity defaults to 1 when missing or invalid" do
    rows = parse("Designation,Quantity\nWidget,\n")
    assert_equal 1, rows.first[:quantity]
  end

  test "drops rows with no designation or reference" do
    rows = parse("Designation,MPN,Quantity\n,,3\nReal,MPN-1,2\n")
    assert_equal 1, rows.size
    assert_equal "Real", rows.first[:designation]
  end

  test "match resolves by mpn, then sku, then case-insensitive name" do
    org = create_organization
    by_mpn = create_part(organization: org, name: "Alpha", mpn: "MPN-1")
    by_sku = create_part(organization: org, name: "Beta", sku: "SKU-1")
    by_name = create_part(organization: org, name: "Widget")

    assert_equal [ by_mpn, "mpn" ], BomParser.match(org, { mpn: "MPN-1", sku: nil, designation: nil })
    assert_equal [ by_sku, "sku" ], BomParser.match(org, { mpn: nil, sku: "SKU-1", designation: nil })
    assert_equal [ by_name, "name" ], BomParser.match(org, { mpn: nil, sku: nil, designation: "widget" })
    assert_equal [ nil, "none" ], BomParser.match(org, { mpn: "ZZZ", sku: nil, designation: nil })
    assert_equal [ by_mpn, "mpn" ], BomParser.match(org, { mpn: "mpn-1", sku: nil, designation: nil })
    assert_equal [ by_sku, "sku" ], BomParser.match(org, { mpn: nil, sku: "sku-1", designation: nil })
  end

  private

  def parse(content)
    file = Tempfile.new([ "bom", ".csv" ], binmode: true)
    file.write(content)
    file.rewind
    BomParser.parse(file.path)
  end
end

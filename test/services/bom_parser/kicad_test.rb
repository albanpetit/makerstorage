require "test_helper"

class BomParser::KicadTest < ActiveSupport::TestCase
  test "reads a KiCad netlist XML, grouping symbols and skipping DNP and excluded ones" do
    rows = BomParser.parse(file_fixture("kicad/sensor_board.xml").to_s)

    assert_equal [ "100nF", "4k7", "BME280" ], rows.map { |r| r[:value] }
    caps, resistor, sensor = rows

    assert_equal 2, caps[:quantity]
    assert_equal "C1, C2", caps[:designators]
    assert_equal "Capacitor_SMD:C_0603_1608Metric", caps[:footprint]
    assert_equal "100nF", caps[:designation]

    assert_equal "C23162", resistor[:sku]
    assert_equal 1, resistor[:quantity]

    assert_equal "BME280", sensor[:mpn]
    assert_equal "Combined humidity and pressure sensor", sensor[:designation]
  end

  test "reads a kicad-cli / Symbol Fields Table CSV, expanding reference ranges when there is no quantity" do
    rows = parse(<<~CSV)
      "Refs","Value","Footprint","MPN","DNP"
      "R1-R4","10k","Resistor_SMD:R_0805_2012Metric","",""
      "C1,C3","1uF","Capacitor_SMD:C_0805_2012Metric","",""
      "U1","NE555","Package_SO:SOIC-8_3.9x4.9mm_P1.27mm","NE555DR",""
      "R5","0R","Resistor_SMD:R_0805_2012Metric","","DNP"
    CSV

    assert_equal 3, rows.size
    assert_equal [ 4, 2, 1 ], rows.map { |r| r[:quantity] }
    assert_equal "R1-R4", rows.first[:designators]
    assert_equal "NE555DR", rows.last[:mpn]
  end

  test "uses the quantity column and groups an ungrouped per-symbol export" do
    rows = parse(<<~CSV)
      Reference,Value,Footprint,Qty
      R1,10k,Resistor_SMD:R_0603_1608Metric,1
      R2,10k,Resistor_SMD:R_0603_1608Metric,1
      C1,100n,Capacitor_SMD:C_0603_1608Metric,3
    CSV

    assert_equal [ [ "R1, R2", 2 ], [ "C1", 3 ] ], rows.map { |r| [ r[:designators], r[:quantity] ] }
  end

  test "skips the legacy bom_csv_grouped_by_value preamble" do
    rows = parse(<<~CSV)
      "Source:","/home/maker/board.kicad_sch"
      "Date:","2024-03-01"
      "Tool:","Eeschema 7.0.10"
      "Generator:","bom_csv_grouped_by_value.py"
      "Component Count:","3"

      "Ref","Qnty","Value","Cmp name","Footprint","Description","Vendor"
      "C1, C2, ","2","100nF","C","Capacitor_SMD:C_0603_1608Metric","Unpolarized capacitor",""
      "U1, ","1","ATtiny85","ATtiny85-20S","Package_SO:SOIC-8_5.3x5.3mm_P1.27mm","",""
    CSV

    assert_equal 2, rows.size
    assert_equal "C1, C2", rows.first[:designators]
    assert_equal 2, rows.first[:quantity]
    assert_equal "Unpolarized capacitor", rows.first[:designation]
    assert_equal "ATtiny85", rows.last[:designation]
  end

  test "reads an EasyEDA BOM export" do
    rows = parse(<<~CSV)
      ID,Name,Designator,Footprint,Quantity,Manufacturer Part,Manufacturer,Supplier,Supplier Part
      1,100nF,"C1,C2,C3",C0603,3,CL10B104KB8NNNC,SAMSUNG,LCSC,C1591
    CSV

    row = rows.first
    assert_equal "100nF", row[:value]
    assert_equal "C0603", row[:footprint]
    assert_equal "CL10B104KB8NNNC", row[:mpn]
    assert_equal "C1591", row[:sku]
    assert_equal 3, row[:quantity]
  end

  test "rejects XML that isn't a KiCad netlist, and malformed XML" do
    assert_raises(BomParser::Kicad::NotANetlist) { parse("<?xml version=\"1.0\"?><bom><item/></bom>") }
    assert_raises(Nokogiri::XML::SyntaxError) { parse("<export><components><comp ref=\"R1\"></export>") }
  end

  test "leaves plain spreadsheet CSVs to the generic parser" do
    rows = parse("Designation;Référence;Quantité\nRésistance;REF-1;7\n")
    assert_equal "REF-1", rows.first[:sku]
    assert_nil rows.first[:designators]
  end

  private

  def parse(content)
    file = Tempfile.new([ "bom", ".csv" ], binmode: true)
    file.write(content)
    file.rewind
    BomParser.parse(file.path)
  end
end

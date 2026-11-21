require "test_helper"

class BomParser::KicadSchematicTest < ActiveSupport::TestCase
  test "reads every placed symbol across hierarchical sheets, once per reference" do
    rows = parse("board/board.kicad_sch", "board/sensor.kicad_sch")

    # Ordered by designator: C1, R1…, U1.
    assert_equal [ "100nF", "10k", "LM358" ], rows.map { |r| r[:value] }
    cap, resistors, opamp = rows

    # R3 sits in a sub-sheet placed twice (R3, R103); its instance under
    # another project doesn't count.
    assert_equal [ 4, "R1, R2, R3, R103" ], resistors.values_at(:quantity, :designators)
    assert_equal "Resistor_SMD:R_0603_1608Metric", resistors[:footprint]
    assert_equal 'Resistor, "thick film"', resistors[:designation]

    assert_equal [ "C14663", 1 ], cap.values_at(:sku, :quantity)
    # Two units of one package are one part.
    assert_equal [ "LM358DR", 1, "U1" ], opamp.values_at(:mpn, :quantity, :designators)
  end

  test "skips power symbols, DNP symbols and symbols left out of the BOM" do
    designators = parse("board/board.kicad_sch").flat_map { |r| r[:designators].split(", ") }

    assert_not_includes designators, "#PWR01"
    assert_not_includes designators, "D1"
    assert_not_includes designators, "H1"
  end

  test "reads KiCad 6 references from the root sheet's symbol instances" do
    rows = parse("kicad6.kicad_sch")

    assert_equal [ [ "4k7", 2, "R5, R6" ] ], rows.map { |r| r.values_at(:value, :quantity, :designators) }
  end

  test "counts unannotated symbols separately" do
    text = file_fixture("kicad/kicad6.kicad_sch").read.sub(/\(symbol_instances.*\)\s*\)\s*\z/m, ")")
    rows = BomParser::KicadSchematic.parse([ [ "draft.kicad_sch", text ] ])

    assert_equal [ [ 2, "R?, R?" ] ], rows.map { |r| r.values_at(:quantity, :designators) }
  end

  test "refuses a file that isn't a KiCad 6+ schematic" do
    assert_raises(BomParser::KicadSchematic::NotASchematic) do
      BomParser::KicadSchematic.parse([ [ "old.kicad_sch", "EESchema Schematic File Version 4\n" ] ])
    end
    assert_raises(BomParser::KicadSchematic::NotASchematic) do
      BomParser::KicadSchematic.parse([ [ "broken.kicad_sch", "(kicad_sch (version 1) (symbol" ] ])
    end
  end

  test "keeps only the symbols of a sheet, so its tree stays small" do
    root = BomParser::KicadSchematic::SExpression.parse(file_fixture("kicad/board/board.kicad_sch").read,
                                                       keep: BomParser::KicadSchematic::BOM_NODES)

    assert_equal "kicad_sch", root.first
    assert root.drop(1).all? { |child| !child.is_a?(Array) || BomParser::KicadSchematic::BOM_NODES.include?(child.first) }
    assert_equal parse("board/board.kicad_sch"), BomParser::KicadSchematic.parse([ [ "board.kicad_sch", file_fixture("kicad/board/board.kicad_sch").read ] ])
  end

  test "refuses sheets far beyond any real schematic instead of reading them whole" do
    stub_const(:MAX_TOKENS_PER_SHEET, 1_000) do
      error = assert_raises(BomParser::KicadSchematic::TooLarge) do
        BomParser::KicadSchematic.parse([ [ "huge.kicad_sch", "(kicad_sch #{'(wire (pts) (xy 1 2)) ' * 200})" ] ])
      end
      assert_equal "huge.kicad_sch", error.message
    end

    # Symbols count against a budget shared by every sheet of the BOM.
    symbol = '(symbol (lib_id "Device:R") (property "Reference" "R1") (property "Value" "10k")) '
    stub_const(:MAX_KEPT_TOKENS, 100) do
      assert_raises(BomParser::KicadSchematic::TooLarge) do
        BomParser::KicadSchematic.parse([ [ "a.kicad_sch", "(kicad_sch #{symbol * 4})" ], [ "b.kicad_sch", "(kicad_sch #{symbol * 4})" ] ])
      end
    end
  end

  private

  def stub_const(name, value)
    previous = BomParser::KicadSchematic.const_get(name)
    BomParser::KicadSchematic.send(:remove_const, name)
    BomParser::KicadSchematic.const_set(name, value)
    yield
  ensure
    BomParser::KicadSchematic.send(:remove_const, name)
    BomParser::KicadSchematic.const_set(name, previous)
  end

  def parse(*names)
    BomParser::KicadSchematic.parse(names.map { |name| [ File.basename(name), file_fixture("kicad/#{name}").read ] })
  end
end

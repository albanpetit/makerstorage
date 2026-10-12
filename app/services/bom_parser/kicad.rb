# frozen_string_literal: true

module BomParser
  # Reads the BOM files EDA tools write, as opposed to hand-made spreadsheets:
  #
  # - KiCad's intermediate netlist XML (`<export><components><comp ref=…>`), the
  #   file KiCad hands to BOM plugins, one <comp> per placed symbol;
  # - KiCad's CSV exports: the Symbol Fields Table / `kicad-cli sch export bom`
  #   ("Refs","Value","Footprint","Qty","DNP", plus any custom fields) and the
  #   legacy `bom_csv_grouped_by_value` plugin (a "Source:/Date:/Tool:" preamble
  #   before its "Ref","Qnty","Value","Cmp name","Footprint" header);
  # - EasyEDA's CSV export ("Designator","Footprint","Manufacturer Part",
  #   "Supplier Part", …), which has the same shape.
  #
  # Every format comes out as BomParser lines, grouped by value + footprint +
  # MPN + supplier part number, with the designators listed and DNP /
  # excluded-from-BOM symbols left out.
  module Kicad
    # Keys are CSV :symbol-converted headers (see BomParser::COLUMN_SYNONYMS);
    # XML <field> names go through the same conversion.
    COLUMN_SYNONYMS = {
      designators: %i[reference references refs ref designator designators],
      value: %i[value comment name],
      footprint: %i[footprint package],
      quantity: %i[qty quantity qnty quantity_per_pcb],
      mpn: %i[mpn manufacturer_part manufacturer_part_number mfr_part mfr_part_number mfr_pn mfr_no mfg_part_number part_number partnumber],
      sku: %i[lcsc lcsc_part lcsc_part_number lcsc_pn jlcpcb_part supplier_part supplier_part_number
              mouser mouser_part_number mouser_pn digikey digikey_part_number digikey_pn farnell farnell_part_number sku],
      description: %i[description desc],
      dnp: %i[dnp do_not_populate do_not_place]
    }.freeze

    # A header line is recognised by a designator column and a footprint column.
    HEADER_PATTERN = /\b(ref|refs|reference|references|designators?)\b/i
    FOOTPRINT_PATTERN = /\bfootprint\b/i
    # How far into a CSV to look for the header (the legacy plugin's preamble is
    # five lines and a blank one).
    PREAMBLE_LINES = 20

    FALSY_DNP = %w[0 false no n -].freeze

    # XML that parses but isn't a KiCad netlist export.
    class NotANetlist < StandardError; end

    module_function

    def xml?(content)
      content.lstrip.start_with?("<")
    end

    # The CSV text from the header line on, or nil when +content+ isn't a
    # KiCad/EasyEDA export (no designator + footprint header near the top).
    def csv_from_header(content)
      lines = content.each_line.first(PREAMBLE_LINES)
      index = lines.index { |line| line.match?(HEADER_PATTERN) && line.match?(FOOTPRINT_PATTERN) }
      return nil unless index

      content.each_line.drop(index).join
    end

    # KiCad netlist XML. Raises Nokogiri::XML::SyntaxError on malformed input,
    # and NotANetlist when the XML isn't a KiCad export.
    def parse_xml(content)
      document = Nokogiri::XML(content, &:strict)
      raise NotANetlist unless document.root&.name == "export"

      group(document.xpath("/export/components/comp").filter_map { |comp| xml_component(comp) })
    end

    def parse_csv(content)
      separator = BomParser.separator(content)
      components = []
      CSV.parse(content, headers: true, header_converters: :symbol, col_sep: separator) do |row|
        component = csv_component(row)
        components << component if component
      end
      group(components)
    end

    # Merges components that are the same part into one line: per-symbol
    # exports (the XML, or an ungrouped CSV) list each R1, R2… separately.
    def group(components)
      components.group_by { |c| c.values_at(:value, :footprint, :mpn, :sku).map { |v| v.to_s.downcase } }.map do |_, same|
        first = same.first
        {
          designation: first[:description].presence || first[:value],
          mpn: first[:mpn],
          sku: first[:sku],
          value: first[:value],
          footprint: first[:footprint],
          designators: same.flat_map { |c| c[:designators] }.compact_blank.join(", ").presence,
          quantity: same.sum { |c| c[:quantity] }
        }
      end
    end

    def xml_component(comp)
      # KiCad 7+ flags DNP and excluded symbols with valueless <property name="dnp"/>
      # / "exclude_from_bom", and (KiCad 8) repeats custom fields as properties
      # with a value; <fields><field name=…> holds the custom fields everywhere.
      properties = comp.xpath("property").to_h { |p| [ symbolize(p["name"]), p["value"].to_s.strip ] }
      return nil if properties.key?(:dnp) || properties.key?(:exclude_from_bom)

      fields = properties.merge(comp.xpath("fields/field").to_h { |f| [ symbolize(f["name"]), f.text.strip ] })
      return nil if dnp?(field(fields, :dnp))

      ref = comp["ref"].to_s.strip
      return nil if ref.start_with?("#") # power symbols and flags

      {
        designators: [ ref ],
        value: comp.at_xpath("value")&.text.to_s.strip.presence,
        footprint: comp.at_xpath("footprint")&.text.to_s.strip.presence,
        mpn: field(fields, :mpn),
        sku: field(fields, :sku),
        description: field(fields, :description) || comp.at_xpath("description")&.text.to_s.strip.presence,
        quantity: 1
      }
    end

    def csv_component(row)
      return nil if dnp?(field(row, :dnp))

      designators = field(row, :designators).to_s.split(/[\s,;]+/).reject { |ref| ref.start_with?("#") }
      value = field(row, :value)
      mpn = field(row, :mpn)
      sku = field(row, :sku)
      return nil if designators.empty? && value.blank? && mpn.blank? && sku.blank?

      quantity = field(row, :quantity).to_i
      quantity = designator_count(designators) if quantity < 1
      quantity = 1 if quantity < 1

      {
        designators: designators,
        value: value,
        footprint: field(row, :footprint),
        mpn: mpn,
        sku: sku,
        description: field(row, :description),
        quantity: quantity
      }
    end

    # First present value among +key+'s synonyms, in a CSV::Row or a Hash.
    def field(source, key)
      COLUMN_SYNONYMS.fetch(key).each do |column|
        value = source[column].to_s.strip
        return value if value.present?
      end
      nil
    end

    def dnp?(value)
      value.present? && !FALSY_DNP.include?(value.downcase)
    end

    # Counts designators, expanding the "R1-R4" ranges kicad-cli writes by
    # default.
    def designator_count(designators)
      designators.sum do |ref|
        match = ref.match(/\A([A-Za-z_]+)(\d+)-\1?(\d+)\z/)
        match ? [ match[3].to_i - match[2].to_i + 1, 1 ].max : 1
      end
    end

    # Same conversion as CSV's :symbol header converter, so XML field names
    # share the CSV synonym table.
    def symbolize(name)
      name.to_s.downcase.gsub(/[^\s\w]+/, "").strip.gsub(/\s+/, "_").to_sym
    end
  end
end

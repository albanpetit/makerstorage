# frozen_string_literal: true

module BomParser
  # Resolves parsed BOM lines against one organization's parts. Build one per
  # import: the value + footprint index is loaded once, on first use.
  #
  # Tries, in order, each an exact case-insensitive match: MPN, the part's own
  # SKU, a supplier's part number (LCSC, Mouser… columns of an EDA export), then
  # value + footprint (an EDA BOM rarely carries an MPN for passives), then name.
  class Matcher
    # Imperial chip sizes, found inside KiCad footprint names such as
    # "R_0603_1608Metric".
    CHIP_SIZE = /(?:\A|_)(01005|0201|0402|0603|0805|1008|1206|1210|1806|1812|2010|2220|2512)(?:_|\z)/

    def initialize(organization)
      @organization = organization
    end

    # Returns [part_or_nil, match_type] where match_type is one of
    # ProjectLine::MATCH_TYPES ("none" when nothing matched).
    def match(line)
      if line[:mpn].present? && (part = find_by(:mpn, line[:mpn]))
        return [ part, "mpn" ]
      end
      if line[:sku].present?
        part = find_by(:sku, line[:sku])
        return [ part, "sku" ] if part

        part = find_by_supplier_sku(line[:sku])
        return [ part, "supplier_sku" ] if part
      end
      if (part = find_by_value_and_footprint(line[:value], line[:footprint]))
        return [ part, "value_footprint" ]
      end
      if line[:designation].present? && (part = find_by(:name, line[:designation]))
        return [ part, "name" ]
      end

      [ nil, "none" ]
    end

    def self.normalize_value(value)
      normalized = value.to_s.unicode_normalize(:nfkc).downcase.delete(" ")
        .tr("μ", "u").sub(/(ohms?|ω|f|h)\z/, "")
      # "4k7" / "2r2" (RKM notation) mean 4.7k / 2.2.
      normalized = normalized.sub(/\A(\d+)([pnumkr])(\d+)\z/) { "#{$1}.#{$3}#{$2 == 'r' ? '' : $2}" }
      normalized.sub(/\.0+(?=[a-z]*\z)/, "").presence
    end

    def self.normalize_package(package)
      package.to_s.downcase.gsub(/[^a-z0-9]/, "").presence
    end

    # Normalized package names a footprint may be stored under in the inventory:
    # the footprint name without its library ("R_0603_1608Metric"), an imperial
    # chip size ("0603") and the package prefix ("SOIC-8" of "SOIC-8_3.9x4.9mm").
    def self.package_candidates(footprint)
      name = footprint.to_s.split(":").last.to_s
      candidates = [ name ]
      candidates << name[CHIP_SIZE, 1]
      tokens = name.split("_")
      # "SOIC-8_3.9x4.9mm_P1.27mm" -> "SOIC-8"; "R_0603_…" was covered above.
      candidates << tokens.first if tokens.size > 1 && tokens.first.length > 2
      candidates.filter_map { |candidate| normalize_package(candidate) }.uniq
    end

    private

    def find_by(column, value)
      @organization.parts.where(Part.arel_table[column].lower.eq(value.downcase)).first
    end

    def find_by_supplier_sku(sku)
      @organization.parts.joins(:part_suppliers)
        .where(PartSupplier.arel_table[:supplier_sku].lower.eq(sku.downcase)).first
    end

    def find_by_value_and_footprint(value, footprint)
      value = self.class.normalize_value(value)
      packages = self.class.package_candidates(footprint)
      return nil if value.nil? || packages.empty?

      id = value_index.fetch(value, []).find { |_, part_packages| part_packages.intersect?(packages) }&.first
      id && @organization.parts.find(id)
    end

    # normalized value => [[part_id, [normalized footprint / package names]], …],
    # in name order so ties go to the same part every time.
    def value_index
      @value_index ||= @organization.parts.where.not(value: [ nil, "" ]).left_joins(:footprint).order(:name)
        .pluck(:id, :value, :package_type, Footprint.arel_table[:name])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(id, value, package_type, footprint), index|
          key = self.class.normalize_value(value)
          index[key] << [ id, [ package_type, footprint ].filter_map { |p| self.class.normalize_package(p) } ] if key
        end
    end
  end
end

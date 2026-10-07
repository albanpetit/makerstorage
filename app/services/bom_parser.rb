# frozen_string_literal: true

require "csv"

# Parses a CSV bill-of-materials / parts export into normalized rows and
# resolves each row against an organization's existing inventory.
#
#   rows = BomParser.parse(file.path)
#   # => [ { designation:, mpn:, sku:, value:, package:, quantity:, ... }, ... ]
#
#   part, match_type = BomParser.match(organization, row)
#
# Column-name handling (French/English/common BOM-export synonyms) and the
# separator sniff live here so both the parts importer and the project BOM
# checker share one source of truth.
module BomParser
  # Column names accepted per logical field, checked in order. CSV::foreach with
  # header_converters: :symbol downcases, underscores whitespace, and strips
  # accents, so "Unit Price" -> :unit_price and "Désignation"/"Quantité" ->
  # :dsignation/:quantit.
  COLUMN_SYNONYMS = {
    name: %i[name designation dsignation],
    category: %i[category categorie catgorie],
    mpn: %i[mpn],
    sku: %i[sku reference ref rfrence],
    manufacturer: %i[manufacturer],
    value: %i[value valeur],
    package: %i[package boitier botier],
    location: %i[location emplacement],
    supplier: %i[supplier fournisseur],
    quantity: %i[quantity quantite quantit qty],
    min_stock_threshold: %i[min_stock_threshold seuil min],
    unit_price: %i[unit_price pu pu_eur price],
    status: %i[status statut]
  }.freeze

  module_function

  # Yields each raw CSV::Row (with symbolized headers) from +path+, sniffing the
  # delimiter (";" vs ",") from the first line. Raises CSV::MalformedCSVError on
  # unparseable input, which callers rescue to report a friendly error.
  def each_row(path)
    content = read_as_utf8(path)
    separator = content.each_line.first.to_s.include?(";") ? ";" : ","
    CSV.parse(content, headers: true, header_converters: :symbol, col_sep: separator) do |row|
      yield row
    end
  end

  # The file's text as UTF-8. Excel on a French Windows saves "CSV (point-virgule)"
  # as Windows-1252, not UTF-8, so anything that isn't valid UTF-8 is read as
  # Windows-1252 instead of being rejected. A UTF-8 byte-order mark is dropped.
  def read_as_utf8(path)
    raw = File.binread(path)
    utf8 = raw.dup.force_encoding(Encoding::UTF_8)
    return utf8.delete_prefix("\uFEFF") if utf8.valid_encoding?

    raw.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  # Returns the first present value among the synonym columns for +field+.
  def value(row, field)
    COLUMN_SYNONYMS.fetch(field).each do |key|
      value = row[key].to_s.strip
      return value if value.present?
    end
    nil
  end

  # Parses +path+ into an array of normalized BOM line hashes. Rows with neither
  # a designation nor any reference are dropped as blank. Quantity defaults to 1
  # (a BOM line implicitly needs at least one) and is floored at 1.
  def parse(path)
    lines = []
    each_row(path) do |row|
      designation = value(row, :name)
      mpn = value(row, :mpn)
      sku = value(row, :sku)
      next if designation.blank? && mpn.blank? && sku.blank?

      quantity = value(row, :quantity).to_i
      quantity = 1 if quantity < 1

      lines << {
        designation: designation,
        mpn: mpn,
        sku: sku,
        quantity: quantity
      }
    end
    lines
  end

  # Resolves a parsed BOM line against +organization+'s parts, trying MPN, then
  # SKU, then an exact case-insensitive name match. Returns [part_or_nil,
  # match_type] where match_type is "mpn"/"sku"/"name"/"none".
  def match(organization, line)
    if line[:mpn].present? && (part = organization.parts.find_by(mpn: line[:mpn]))
      return [ part, "mpn" ]
    end
    if line[:sku].present? && (part = organization.parts.find_by(sku: line[:sku]))
      return [ part, "sku" ]
    end
    if line[:designation].present? &&
       (part = organization.parts.where("LOWER(name) = ?", line[:designation].downcase).first)
      return [ part, "name" ]
    end

    [ nil, "none" ]
  end
end

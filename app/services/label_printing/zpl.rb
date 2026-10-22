# frozen_string_literal: true

module LabelPrinting
  # ZPL II for Zebra (and ZPL-compatible) thermal printers: each label is one
  # ^GFA graphic field covering the whole label.
  module Zpl
    DPIS = [ 203, 300, 600 ].freeze

    module_function

    def dots(mm, dpi)
      (mm.to_f * dpi / 25.4).round
    end

    # The print job for +bitmaps+, each a packed 1-bit image (rows of
    # ceil(width / 8) bytes, most significant bit first, 1 = black).
    def encode(bitmaps, width:, height:)
      row_bytes = (width + 7) / 8
      total = row_bytes * height
      bitmaps.map do |bitmap|
        "^XA^PW#{width}^LL#{height}^LH0,0^FO0,0" \
          "^GFA,#{total},#{total},#{row_bytes},#{bitmap.unpack1('H*').upcase}^FS^PQ1^XZ\n"
      end.join.b
    end
  end
end

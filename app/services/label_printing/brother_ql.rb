# frozen_string_literal: true

module LabelPrinting
  # Brother QL raster protocol (QL-700/710W/720NW/800/810W/820NWB and other
  # 720-dot, 300 dpi models), as documented in Brother's "Raster Command
  # Reference" and implemented by the brother_ql project. Each label is sent as
  # its own job: invalidate, initialize, raster mode, media info, cut, margins,
  # uncompressed raster lines, print.
  module BrotherQl
    DOTS_PER_MM = 300 / 25.4
    HEAD_DOTS = 720
    LINE_BYTES = HEAD_DOTS / 8

    Media = Data.define(:name, :width_mm, :length_mm, :printable_width, :printable_length, :right_offset) do
      def continuous? = length_mm.nil?
    end

    # Printable area (dots) and right offset per DK roll, from brother_ql's
    # label table. Continuous rolls print whatever length is asked for.
    MEDIA = {
      "29" => Media.new("29 mm continuous (DK-22210)", 29, nil, 306, nil, 6),
      "38" => Media.new("38 mm continuous (DK-22225)", 38, nil, 413, nil, 12),
      "50" => Media.new("50 mm continuous (DK-22223)", 50, nil, 554, nil, 12),
      "62" => Media.new("62 mm continuous (DK-22205)", 62, nil, 696, nil, 12),
      "17x54" => Media.new("17 × 54 mm die-cut (DK-11204)", 17, 54, 165, 566, 0),
      "23x23" => Media.new("23 × 23 mm die-cut (DK-11221)", 23, 23, 202, 202, 42),
      "29x90" => Media.new("29 × 90 mm die-cut (DK-11201)", 29, 90, 306, 991, 6),
      "38x90" => Media.new("38 × 90 mm die-cut (DK-11208)", 38, 90, 413, 991, 12),
      "52x29" => Media.new("52 × 29 mm die-cut (DK-11220)", 52, 29, 578, 271, 0),
      "62x29" => Media.new("62 × 29 mm die-cut (DK-11209)", 62, 29, 696, 271, 12),
      "62x100" => Media.new("62 × 100 mm die-cut (DK-11202)", 62, 100, 696, 1109, 12)
    }.freeze

    # Continuous rolls are fed with a margin before and after the label.
    CONTINUOUS_FEED_MARGIN = 35

    module_function

    # Raster lines for a label on +media+ (+length_mm+ for continuous rolls).
    def raster_lines(media, length_mm)
      media.continuous? ? (length_mm.to_f * DOTS_PER_MM).round : media.printable_length
    end

    # The print job for +bitmaps+, each a packed 1-bit image (rows of
    # ceil(printable_width / 8) bytes, most significant bit first, 1 = black)
    # of +lines+ rows.
    def encode(bitmaps, media:, lines:)
      row_bytes = (media.printable_width + 7) / 8
      job = +"".b
      bitmaps.each do |bitmap|
        job << ("\x00" * 200).b      # invalidate
        job << "\e@".b               # initialize
        job << "\eia\x01".b          # switch to raster mode
        job << print_information(media, lines)
        job << "\eiM\x40".b          # auto cut
        job << "\eiA\x01".b          # cut every label
        job << "\eiK\x08".b          # cut at end
        job << "\eid".b << [ media.continuous? ? CONTINUOUS_FEED_MARGIN : 0 ].pack("v")
        lines.times do |y|
          job << "g\x00".b << LINE_BYTES.chr << raster_line(bitmap.byteslice(y * row_bytes, row_bytes), media)
        end
        job << "\x1A".b              # print, then feed and cut
      end
      job
    end

    # ESC i z: which fields the printer checks (kind, width, length when the
    # label has one, quality, recover), the media and the number of raster lines.
    def print_information(media, lines)
      flags = 0x80 | 0x40 | 0x02 | 0x04
      flags |= 0x08 unless media.continuous?
      kind = media.continuous? ? 0x0A : 0x0B
      "\eiz".b + [ flags, kind, media.width_mm, media.length_mm || 0 ].pack("C4") + [ lines ].pack("V") + "\x00\x00".b
    end

    # One head line: the printer prints it mirrored, so the label's bits go in
    # reverse order, starting +right_offset+ dots from the head's edge.
    def raster_line(row, media)
      bits = row.to_s.unpack1("B*").ljust(media.printable_width, "0")[0, media.printable_width].reverse
      line = ("0" * media.right_offset) + bits
      [ line.ljust(HEAD_DOTS, "0") ].pack("B*")
    end
  end
end

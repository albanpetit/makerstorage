require "test_helper"

class LabelPrinting::BrotherQlTest < ActiveSupport::TestCase
  MEDIA = LabelPrinting::BrotherQl::MEDIA

  test "a die-cut job sets the media, cuts, and ends with a print command" do
    media = MEDIA["62x29"]
    bitmap = "\x00".b * (87 * 271)
    job = LabelPrinting::BrotherQl.encode([ bitmap ], media: media, lines: 271)

    assert job.start_with?(("\x00" * 200).b + "\e@\eia\x01".b)
    info = job[job.index("\eiz".b) + 3, 10].bytes
    assert_equal [ 0xCE, 0x0B, 62, 29 ], info.first(4)
    assert_equal 271, info[4, 4].pack("C4").unpack1("V")
    assert_includes job, "\eid\x00\x00".b
    assert_equal 271, job.scan("g\x00Z".b).size
    assert job.end_with?("\x1A".b)
  end

  test "a continuous job leaves the length out and keeps the feed margin" do
    job = LabelPrinting::BrotherQl.encode([ "\x00".b * (87 * 100) ], media: MEDIA["62"], lines: 100)
    info = job[job.index("\eiz".b) + 3, 4].bytes
    assert_equal [ 0xC6, 0x0A, 62, 0 ], info
    assert_includes job, "\eid#\x00".b
  end

  test "each label is its own job" do
    job = LabelPrinting::BrotherQl.encode([ "\x00".b * (87 * 10) ] * 3, media: MEDIA["62"], lines: 10)
    assert_equal 3, job.scan("\x1A".b).size
  end

  test "raster lines are mirrored and placed after the right offset" do
    media = MEDIA["62x29"] # 696 dots, 12-dot offset
    row = ("\x80".b + "\x00".b * 86) # only the label's first (leftmost) dot is black
    line = LabelPrinting::BrotherQl.raster_line(row, media)

    assert_equal 90, line.bytesize
    bits = line.unpack1("B*")
    assert_equal [ 12 + 696 - 1 ], (0...bits.size).select { |i| bits[i] == "1" }
  end

  test "raster_lines follows the roll length for continuous media" do
    assert_equal 343, LabelPrinting::BrotherQl.raster_lines(MEDIA["62"], 29)
    assert_equal 991, LabelPrinting::BrotherQl.raster_lines(MEDIA["29x90"], nil)
  end
end

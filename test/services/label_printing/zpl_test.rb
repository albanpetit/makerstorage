require "test_helper"

class LabelPrinting::ZplTest < ActiveSupport::TestCase
  test "each label is a full-size graphic field" do
    job = LabelPrinting::Zpl.encode([ "\xF0\x0F".b, "\x00\xFF".b ], width: 16, height: 1)
    labels = job.lines
    assert_equal 2, labels.size
    assert_equal "^XA^PW16^LL1^LH0,0^FO0,0^GFA,2,2,2,F00F^FS^PQ1^XZ\n", labels.first
    assert_includes labels.last, ",00FF^FS"
  end

  test "dots converts millimetres at the resolution" do
    assert_equal 203, LabelPrinting::Zpl.dots(25.4, 203)
    assert_equal 591, LabelPrinting::Zpl.dots(50, 300)
  end
end

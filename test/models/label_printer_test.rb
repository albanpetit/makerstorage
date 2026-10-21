require "test_helper"

class LabelPrinterTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
  end

  def build_printer(**attrs)
    @org.label_printers.build({ name: "Workshop QL", protocol: "brother_ql", host: "192.168.1.50", port: 9100, media: "62x29" }.merge(attrs))
  end

  test "a Brother die-cut label prints its printable area" do
    printer = build_printer
    assert printer.valid?
    assert_equal({ width: 696, height: 271, dots_per_mm: 300 / 25.4 }, printer.geometry)
    assert_equal "62 × 29 mm", printer.size_label
    assert_equal 87 * 271, printer.bitmap_bytesize
  end

  test "a Brother continuous roll needs a length and prints that many lines" do
    printer = build_printer(media: "62", length_mm: nil)
    assert_not printer.valid?
    assert printer.errors.of_kind?(:length_mm, :not_a_number)

    printer.length_mm = 40
    assert printer.valid?
    assert_equal 472, printer.geometry[:height]
    assert_equal "62 × 40 mm", printer.size_label
  end

  test "a Zebra printer needs a size and a resolution" do
    printer = build_printer(protocol: "zpl", media: nil, width_mm: 50.8, length_mm: 25.4, dpi: 203)
    assert printer.valid?
    assert_equal 406, printer.geometry[:width]
    assert_equal 203, printer.geometry[:height]
    assert_equal "50.8 × 25.4 mm", printer.size_label

    printer.dpi = 250
    assert_not printer.valid?
    assert printer.errors.of_kind?(:dpi, :inclusion)
  end

  test "rejects unknown media, protocols and non-printer ports" do
    assert build_printer(media: "99x99").invalid?
    assert build_printer(protocol: "ipp").invalid?
    printer = build_printer(port: 6379)
    assert printer.invalid?
    assert printer.errors.include?(:port)
    assert build_printer(port: 9101).valid?
  end

  test "rejects a host with anything but a name or an address" do
    assert build_printer(host: "printer.local").valid?
    assert build_printer(host: "fd00::12").valid?
    assert build_printer(host: "http://printer/").invalid?
    assert build_printer(host: "printer; rm").invalid?
  end

  test "print_bitmaps encodes the job for the protocol and sends it" do
    printer = build_printer(protocol: "zpl", media: nil, width_mm: 10, length_mm: 10, dpi: 203)
    printer.save!
    sent = nil
    stub_singleton(LabelPrinting::Network, :deliver, ->(host, port, data) { sent = [ host, port, data ] }) do
      printer.print_bitmaps([ "\x00".b * printer.bitmap_bytesize ])
    end

    assert_equal [ "192.168.1.50", 9100 ], sent.first(2)
    assert sent.last.start_with?("^XA^PW80^LL80")
  end

  test "is destroyed with its organization and kept by a reset" do
    build_printer.save!
    assert_no_difference -> { LabelPrinter.count } do
      @org.reset_data!
    end
    assert_difference -> { LabelPrinter.count }, -1 do
      @org.destroy!
    end
  end
end

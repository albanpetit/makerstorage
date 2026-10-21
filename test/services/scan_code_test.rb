require "test_helper"

class ScanCodeTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @lookup = ScanCode.new(@org)
  end

  test "normalize keeps the code of a scanned label link and leaves other text alone" do
    assert_equal "MS-00042", ScanCode.normalize(" https://lab.example/scan?code=MS-00042 ")
    assert_equal "https://example.com/datasheet", ScanCode.normalize("https://example.com/datasheet")
    assert_equal "R-10K", ScanCode.normalize("R-10K")
  end

  test "part matches the IPN first, then barcode, SKU or MPN, and the part: fallback" do
    by_mpn = create_part(organization: @org, mpn: "ABC")
    by_ipn = create_part(organization: @org, ipn: "abc")

    assert_equal by_ipn, @lookup.part("ABC")
    assert_equal by_mpn, @lookup.part("part:#{by_mpn.id}")
    assert_nil @lookup.part("part:#{create_part(organization: create_organization).id}")
  end

  test "location matches the zone code or the zone: fallback within the organization" do
    zone = create_storage_location(organization: @org, code: "T1")
    foreign = create_storage_location(organization: create_organization, code: "T2")

    assert_equal zone, @lookup.location("t1")
    assert_equal zone, @lookup.location("zone:#{zone.id}")
    assert_nil @lookup.location("T2")
    assert_nil @lookup.location("zone:#{foreign.id}")
  end
end

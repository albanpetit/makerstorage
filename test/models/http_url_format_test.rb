require "test_helper"

# URL fields (organization and supplier websites, part supplier links) end up
# in hrefs, so they must hold a whole http(s) URL and nothing else.
class HttpUrlFormatTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @supplier = create_supplier(organization: @org)
  end

  test "a plain http or https URL is accepted" do
    @org.website = "https://fablab.example.org/stock"
    @org.valid?
    assert_empty @org.errors[:website]

    @supplier.website = "http://supplier.example.com"
    assert @supplier.valid?
  end

  test "a javascript: URL hiding an http one is refused everywhere" do
    url = "javascript:alert(document.cookie)//http://x.com"
    part = create_part(organization: @org)

    @org.website = url
    assert_not @org.valid?
    assert @org.errors[:website].any?

    @supplier.website = url
    assert_not @supplier.valid?
    assert @supplier.errors[:website].any?

    link = PartSupplier.new(part: part, supplier: @supplier, url: url)
    assert_not link.valid?
    assert link.errors[:url].any?
  end

  test "text around a URL is refused" do
    @supplier.website = "see https://supplier.example.com"
    assert_not @supplier.valid?
  end
end

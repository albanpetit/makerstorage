require "test_helper"

class SupplierCatalog::RemoteFileTest < ActiveSupport::TestCase
  RemoteFile = SupplierCatalog::RemoteFile

  test "rejects non-http URLs" do
    assert_nil RemoteFile.safe_uri("ftp://example.com/file.pdf")
    assert_nil RemoteFile.safe_uri("file:///etc/passwd")
    assert_nil RemoteFile.safe_uri("not a url")
  end

  test "public_ip? rejects loopback, private and link-local addresses" do
    refute RemoteFile.public_ip?("127.0.0.1")
    refute RemoteFile.public_ip?("10.0.0.5")
    refute RemoteFile.public_ip?("192.168.1.10")
    refute RemoteFile.public_ip?("172.16.0.1")
    refute RemoteFile.public_ip?("169.254.169.254") # cloud metadata endpoint
    refute RemoteFile.public_ip?("100.64.0.1")      # carrier-grade NAT
    refute RemoteFile.public_ip?("::1")
  end

  test "public_ip? accepts routable public addresses" do
    assert RemoteFile.public_ip?("8.8.8.8")
    assert RemoteFile.public_ip?("1.1.1.1")
  end

  test "safe_uri rejects a URL whose host resolves to a private address" do
    # A literal private IP host must be rejected without any network access.
    assert_nil RemoteFile.safe_uri("http://169.254.169.254/latest/meta-data/")
    assert_nil RemoteFile.safe_uri("https://127.0.0.1/secret")
  end

  test "safe_uri accepts a public https URL" do
    refute_nil RemoteFile.safe_uri("https://8.8.8.8/datasheet.pdf")
  end

  test "download sends browser headers so supplier CDNs don't block the request" do
    captured_headers = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["Content-Type"] = "image/png"
    response.define_singleton_method(:read_body) { |&block| block.call("PNG-image-bytes") }

    fake_http = Object.new
    fake_http.define_singleton_method(:ipaddr=) { |_| }
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:start) { |&block| block.call }
    fake_http.define_singleton_method(:request_get) do |_request_uri, headers, &block|
      captured_headers = headers
      block.call(response)
    end

    # A literal public IP avoids any DNS/network access during the test.
    stub_singleton(Net::HTTP, :new, ->(*) { fake_http }) do
      result = RemoteFile.download("https://8.8.8.8/image.png")
      assert result, "expected a successful download"
      assert_equal "image/png", result.content_type
    end

    # A browser-like User-Agent plus Accept/Accept-Language is what gets past
    # Akamai bot protection; and we must not set Accept-Encoding ourselves or
    # Net::HTTP hands back undecoded gzip bytes.
    assert_match(/Mozilla/, captured_headers["User-Agent"])
    assert captured_headers["Accept"].present?
    assert captured_headers["Accept-Language"].present?
    assert_nil captured_headers["Accept-Encoding"]
  end

  test "download aborts once the streamed body exceeds max_bytes" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["Content-Type"] = "application/pdf"
    # Stream chunks that together blow past the cap; the reader must stop early
    # instead of buffering the whole thing into memory.
    response.define_singleton_method(:read_body) do |&block|
      3.times { block.call("x" * 40) }
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:ipaddr=) { |_| }
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:start) { |&block| block.call }
    fake_http.define_singleton_method(:request_get) { |_uri, _headers, &block| block.call(response) }

    stub_singleton(Net::HTTP, :new, ->(*) { fake_http }) do
      result = RemoteFile.download("https://8.8.8.8/big.pdf", max_bytes: 50)
      assert_nil result, "expected an oversized response to be rejected"
    end
  end
end

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

  test "public_ip? rejects every other special-purpose IPv4 block" do
    %w[0.0.0.1 192.0.0.8 192.0.2.1 198.18.0.1 198.51.100.7 203.0.113.9 224.0.0.1 239.255.255.250 240.0.0.1 255.255.255.255].each do |address|
      refute RemoteFile.public_ip?(address), address
    end
  end

  test "public_ip? rejects IPv6 forms that embed a private IPv4 address" do
    %w[::ffff:127.0.0.1 ::127.0.0.1 64:ff9b::7f00:1 64:ff9b::a9fe:a9fe 64:ff9b:1::a00:1 2002:7f00:1::1 2002:c0a8:101::1].each do |address|
      refute RemoteFile.public_ip?(address), address
    end
  end

  test "public_ip? rejects non-public IPv6 blocks" do
    %w[:: fd00::1 fe80::1 fec0::1 ff02::1 2001:db8::1 2001::1 100::1].each do |address|
      refute RemoteFile.public_ip?(address), address
    end
  end

  test "public_ip? accepts routable public addresses" do
    assert RemoteFile.public_ip?("8.8.8.8")
    assert RemoteFile.public_ip?("1.1.1.1")
    assert RemoteFile.public_ip?("2606:4700:4700::1111")
    assert RemoteFile.public_ip?("::ffff:8.8.8.8")
    assert RemoteFile.public_ip?("64:ff9b::808:808")
    assert RemoteFile.public_ip?("2002:808:808::1")
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

  test "download ignores a proxy from the environment so the validated IP is what it reaches" do
    connection = nil
    original = Net::HTTP.method(:new)
    building = lambda do |*args|
      connection = original.call(*args)
      connection.define_singleton_method(:start) { nil }
      connection
    end

    # Net::HTTP reads http_proxy for both schemes.
    previous = ENV["http_proxy"]
    ENV["http_proxy"] = "http://10.0.0.1:3128"
    stub_singleton(Net::HTTP, :new, building) do
      RemoteFile.download("https://8.8.8.8/datasheet.pdf")
    end

    assert_not connection.proxy?
    assert_equal "8.8.8.8", connection.ipaddr
  ensure
    ENV["http_proxy"] = previous
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

  test "safe_uri rejects a host name that resolves to a private address, or to nothing" do
    stub_singleton(Resolv, :getaddresses, ->(host) { host == "internal.example" ? [ "93.184.216.34", "10.0.0.7" ] : [] }) do
      assert_nil RemoteFile.safe_uri("https://internal.example/file.pdf"), "one private address is enough to refuse"
      assert_nil RemoteFile.safe_uri("https://nowhere.example/file.pdf")
    end
  end

  test "safe_uri refuses a host the resolver fails on" do
    stub_singleton(Resolv, :getaddresses, ->(_) { raise Resolv::ResolvError }) do
      assert_nil RemoteFile.safe_uri("https://broken.example/file.pdf")
    end
  end

  test "public_ip? refuses something that isn't an address" do
    refute RemoteFile.public_ip?("not-an-ip")
  end

  test "download follows a redirect to a public host" do
    responses = {
      "/old.pdf" => redirect_to("https://1.1.1.1/new"),
      "/new" => ok("application/pdf", "%PDF-1.7")
    }
    with_paths(responses) do
      result = RemoteFile.download("https://8.8.8.8/old.pdf", default_filename: "datasheet")
      assert result
      assert_equal "%PDF-1.7", result.io.read
      assert_equal "new.pdf", result.filename, "the extension comes from the content type"
    end
  end

  test "download refuses a redirect to a private address" do
    with_paths("/file.pdf" => redirect_to("http://169.254.169.254/latest/meta-data/")) do
      assert_nil RemoteFile.download("https://8.8.8.8/file.pdf")
    end
  end

  test "download gives up after too many redirects" do
    with_paths("/loop" => redirect_to("https://8.8.8.8/loop")) do
      assert_nil RemoteFile.download("https://8.8.8.8/loop")
    end
  end

  test "download returns nil on an error status or a failure" do
    with_paths("/missing.pdf" => Net::HTTPNotFound.new("1.1", "404", "Not Found")) do
      assert_nil RemoteFile.download("https://8.8.8.8/missing.pdf")
    end

    stub_singleton(Net::HTTP, :new, ->(*) { raise Errno::ECONNREFUSED }) do
      assert_nil RemoteFile.download("https://8.8.8.8/file.pdf")
    end
  end

  private

  def ok(content_type, body)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
      response["Content-Type"] = content_type
      response.define_singleton_method(:read_body) { |&block| block.call(body) }
    end
  end

  def redirect_to(location)
    Net::HTTPFound.new("1.1", "302", "Found").tap { |response| response["Location"] = location }
  end

  # Net::HTTP answering each request path from +responses+.
  def with_paths(responses, &)
    build = lambda do |*|
      http = Object.new
      %i[ipaddr= use_ssl= open_timeout= read_timeout=].each { |name| http.define_singleton_method(name) { |_| } }
      http.define_singleton_method(:start) { |&block| block.call }
      http.define_singleton_method(:request_get) { |path, _headers, &block| block.call(responses.fetch(path)) }
      http
    end
    stub_singleton(Net::HTTP, :new, build, &)
  end
end

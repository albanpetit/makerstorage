require "test_helper"

class LabelPrinting::NetworkTest < ActiveSupport::TestCase
  Network = LabelPrinting::Network

  test "only private network addresses are allowed" do
    %w[192.168.1.20 10.0.0.5 172.20.1.1 100.101.102.103 fd12::1 ::ffff:192.168.1.20].each do |ip|
      assert Network.allowed_ip?(ip), "#{ip} should be allowed"
    end
    %w[127.0.0.1 169.254.169.254 8.8.8.8 0.0.0.0 ::1 fe80::1 172.32.0.1 ::ffff:127.0.0.1 nonsense].each do |ip|
      assert_not Network.allowed_ip?(ip), "#{ip} should be refused"
    end
  end

  test "only printer ports are allowed" do
    assert Network.allowed_port?(9100)
    assert Network.allowed_port?("6101")
    assert_not Network.allowed_port?(22)
    assert_not Network.allowed_port?(6379)
  end

  test "deliver refuses loopback, public hosts and other ports before connecting" do
    error = assert_raises(Network::Error) { Network.deliver("127.0.0.1", 9100, "x") }
    assert_match "isn't a local network address", error.message
    assert_raises(Network::Error) { Network.deliver("8.8.8.8", 9100, "x") }
    error = assert_raises(Network::Error) { Network.deliver("192.168.1.20", 22, "x") }
    assert_match "isn't a printer port", error.message
  end

  test "a host name is refused when any of its addresses is outside the ranges" do
    stub_singleton(Resolv, :getaddresses, ->(_host) { [ "192.168.1.20", "127.0.0.1" ] }) do
      assert_raises(Network::Error) { Network.address_for("printer.local") }
    end
    stub_singleton(Resolv, :getaddresses, ->(_host) { [] }) do
      assert_raises(Network::Error) { Network.address_for("missing.local") }
    end
    stub_singleton(Resolv, :getaddresses, ->(_host) { [ "192.168.1.20" ] }) do
      assert_equal "192.168.1.20", Network.address_for("printer.local")
    end
  end

  test "deliver writes the job to the printer's socket" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    received = Thread.new { client = server.accept; data = client.read; client.close; data }

    stub_singleton(Network, :address_for, ->(_host) { "127.0.0.1" }) do
      stub_singleton(Network, :allowed_port?, ->(_port) { true }) do
        assert Network.deliver("printer.local", port, "^XA^XZ")
      end
    end
    assert_equal "^XA^XZ", received.value
  ensure
    server&.close
  end

  test "an unreachable printer raises a readable error" do
    stub_singleton(Socket, :tcp, ->(*_args, **_kwargs) { raise Errno::ECONNREFUSED }) do
      error = assert_raises(Network::Error) { Network.deliver("192.168.1.20", 9100, "x") }
      assert_match "Could not reach the printer at 192.168.1.20:9100", error.message
    end
  end

  # Telling "refused" from "timed out" would let anyone probe the server's network.
  test "the system error is not shown" do
    [ Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH ].map do |error_class|
      stub_singleton(Socket, :tcp, ->(*_args, **_kwargs) { raise error_class }) do
        assert_raises(Network::Error) { Network.deliver("192.168.1.20", 9100, "x") }.message
      end
    end.uniq.then { |messages| assert_equal 1, messages.size, messages.inspect }
  end

  test "NETWORK_PRINTING=false turns it off" do
    original = Rails.configuration.x.network_printing
    Rails.configuration.x.network_printing = false
    error = assert_raises(Network::Error) { Network.deliver("192.168.1.20", 9100, "x") }
    assert_match "turned off", error.message
  ensure
    Rails.configuration.x.network_printing = original
  end
end

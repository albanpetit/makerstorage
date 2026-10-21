# frozen_string_literal: true

require "socket"
require "resolv"
require "ipaddr"

module LabelPrinting
  # Sends a raw print job to a label printer on the local network (the
  # "RAW"/JetDirect port, 9100 by default).
  #
  # Printers are set up by organization admins, so on a shared instance this is
  # a server-side connection anyone with an organization could aim. It is kept
  # to what a label printer needs: private and carrier-grade NAT (Tailscale)
  # addresses only (never loopback, link-local or public ones) and printer
  # ports only, so a job can't reach the server's own services or a cloud
  # metadata endpoint. The host is resolved once and the socket pinned to the
  # checked address. NETWORK_PRINTING=false turns the feature off.
  module Network
    class Error < StandardError; end

    PORTS = [ *9100..9109, 6101 ].freeze
    ALLOWED_RANGES = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7].map { |range| IPAddr.new(range) }.freeze
    CONNECT_TIMEOUT = 5
    WRITE_TIMEOUT = 30

    module_function

    def enabled?
      Rails.configuration.x.network_printing
    end

    def allowed_port?(port)
      PORTS.include?(port.to_i)
    end

    def allowed_ip?(address)
      ip = IPAddr.new(address)
      ip = ip.native if ip.ipv4_mapped?
      ALLOWED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end

    # The address to connect to for +host+, or raises Error when it doesn't
    # resolve or any of its addresses is outside the allowed ranges.
    def address_for(host)
      addresses = begin
        IPAddr.new(host)
        [ host ]
      rescue IPAddr::InvalidAddressError
        Resolv.getaddresses(host)
      end
      raise Error, "#{host} could not be found on the network." if addresses.empty?
      raise Error, "#{host} isn't a local network address (10.x, 172.16–31.x, 192.168.x)." unless addresses.all? { |a| allowed_ip?(a) }

      addresses.first
    end

    def deliver(host, port, data)
      raise Error, "Network printing is turned off on this server." unless enabled?
      raise Error, "Port #{port} isn't a printer port (#{PORTS.first}–#{PORTS[-2]} or #{PORTS.last})." unless allowed_port?(port)

      address = address_for(host)
      Socket.tcp(address, port.to_i, connect_timeout: CONNECT_TIMEOUT) do |socket|
        socket.timeout = WRITE_TIMEOUT
        socket.write(data)
        socket.close_write
      end
      true
    rescue Error
      raise
    rescue SystemCallError, IOError, SocketError, Resolv::ResolvError => e
      raise Error, "Could not reach the printer at #{host}:#{port} (#{e.message})."
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "resolv"
require "ipaddr"

module SupplierCatalog
  # Best-effort downloader for supplier-provided asset URLs (datasheets, images)
  # so they can be attached to Active Storage on part creation.
  #
  # Because the URL originates from a lookup result relayed through the client,
  # this guards against SSRF: http(s) only, and the resolved host must not point
  # at a private/loopback/link-local/reserved address (each redirect hop is
  # re-checked). Size and redirect counts are capped. Any failure returns nil —
  # a missing datasheet must never break part creation.
  module RemoteFile
    DEFAULT_MAX_BYTES = 25 * 1024 * 1024 # 25 MB
    MAX_REDIRECTS = 3
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    # Mouser's assets sit behind Akamai bot protection that 403s (or silently
    # stalls into a read timeout) any request that doesn't look like a real
    # browser — a plain "User-Agent" is not enough, it also inspects Accept /
    # Accept-Language. Send a realistic browser header set so downloads succeed.
    #
    # Deliberately no Accept-Encoding: Net::HTTP only auto-decompresses gzip when
    # it sets that header itself. Setting it here would hand back raw gzip bytes
    # and corrupt every attachment.
    BROWSER_HEADERS = {
      "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Accept" => "text/html,application/pdf,image/avif,image/webp,image/png,image/*,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9"
    }.freeze

    Download = Struct.new(:io, :filename, :content_type, keyword_init: true)
    # Result of a successful fetch: the response (for headers), the already-read
    # body (streamed under the size cap), and the final URI after redirects.
    Fetched = Struct.new(:response, :body, :uri, keyword_init: true)

    module_function

    # Returns a Download (io/filename/content_type) or nil on any failure.
    def download(url, max_bytes: DEFAULT_MAX_BYTES, default_filename: "attachment")
      uri = safe_uri(url)
      return nil unless uri

      result = fetch(uri, max_bytes: max_bytes)
      return nil unless result

      body = result.body
      return nil if body.empty?

      Download.new(
        io: StringIO.new(body),
        filename: filename_for(result.uri, result.response, default_filename),
        content_type: result.response["Content-Type"].to_s.split(";").first.presence
      )
    rescue StandardError => e
      Rails.logger.warn("[SupplierCatalog::RemoteFile] failed to download #{url}: #{e.class}: #{e.message}")
      nil
    end

    # Parses +url+ and rejects anything that isn't a public http(s) endpoint.
    def safe_uri(url)
      uri = URI.parse(url.to_s.strip)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
      return nil unless public_host?(uri.host)

      uri
    rescue URI::InvalidURIError
      nil
    end

    # True only when every resolved address for +host+ is publicly routable.
    def public_host?(host)
      validated_ip(host).present?
    end

    # Resolves +host+ and returns a single validated public IP to connect to, or
    # nil if any resolved address is non-public. The returned IP is what we pin
    # the socket to (see #fetch) so the connection can't be re-resolved to an
    # internal address after the check — the DNS-rebinding TOCTOU window.
    def validated_ip(host)
      addresses = resolve(host)
      return nil if addresses.empty?
      return nil unless addresses.all? { |ip| public_ip?(ip) }

      addresses.first
    rescue Resolv::ResolvError, IPAddr::InvalidAddressError
      nil
    end

    def resolve(host)
      # If the host is already a literal IP, use it directly; otherwise resolve.
      IPAddr.new(host)
      [ host ]
    rescue IPAddr::InvalidAddressError
      Resolv.getaddresses(host)
    end

    # Every IANA special-purpose block that isn't a public internet host:
    # "this network", private, carrier-grade NAT, loopback, link-local,
    # documentation, benchmarking, multicast, reserved, unique-local... An
    # allowlist would be stricter still, but public space has no compact one.
    NON_PUBLIC_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 100::/64 2001::/23 2001:db8::/32 fc00::/7 fe80::/10
      fec0::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    # IPv6 forms that carry an IPv4 address the connection may end up at:
    # IPv4-mapped, IPv4-compatible, NAT64 (well-known and local-use), 6to4.
    EMBEDDED_IPV4_RANGES = {
      IPAddr.new("::ffff:0:0/96") => ->(ip) { ip.to_i & 0xffff_ffff },
      IPAddr.new("::/96") => ->(ip) { ip.to_i & 0xffff_ffff },
      IPAddr.new("64:ff9b::/96") => ->(ip) { ip.to_i & 0xffff_ffff },
      IPAddr.new("64:ff9b:1::/48") => ->(ip) { ip.to_i & 0xffff_ffff },
      IPAddr.new("2002::/16") => ->(ip) { (ip.to_i >> 80) & 0xffff_ffff }
    }.freeze

    def public_ip?(address)
      ip = IPAddr.new(address)
      return false if NON_PUBLIC_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }

      if ip.ipv6?
        EMBEDDED_IPV4_RANGES.each do |range, extract|
          next unless range.include?(ip)

          return public_ip?(IPAddr.new(extract.call(ip), Socket::AF_INET).to_s)
        end
      end

      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def fetch(uri, max_bytes:, redirects_left: MAX_REDIRECTS)
      # Re-resolve and re-validate on every hop, then pin the socket to the exact
      # IP we validated. Net::HTTP would otherwise resolve uri.host again when it
      # opens the connection, so a host that passes the public-IP check could
      # rebind to an internal address before connect. `ipaddr=` connects to the
      # pinned IP while still sending the hostname for SNI/cert verification.
      # The explicit nil proxy keeps Net::HTTP from picking one up from
      # http_proxy (read for both schemes): through a proxy, the pinned IP would
      # no longer be what the request actually reaches.
      ip = validated_ip(uri.host)
      return nil unless ip

      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.ipaddr = ip
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      http.start do
        http.request_get(uri.request_uri, BROWSER_HEADERS) do |response|
          case response
          when Net::HTTPSuccess
            body = read_capped_body(response, max_bytes)
            return nil if body.nil?

            return Fetched.new(response: response, body: body, uri: uri)
          when Net::HTTPRedirection
            return nil if redirects_left <= 0

            location = response["Location"]
            target = safe_uri(URI.join(uri.to_s, location.to_s).to_s)
            return nil unless target

            return fetch(target, max_bytes: max_bytes, redirects_left: redirects_left - 1)
          else
            return nil
          end
        end
      end
    end

    # Streams the response body chunk by chunk, aborting (returns nil) as soon as
    # it exceeds +max_bytes+ so an oversized/endless response can't be buffered
    # whole into memory.
    def read_capped_body(response, max_bytes)
      body = +""
      response.read_body do |chunk|
        body << chunk
        return nil if body.bytesize > max_bytes
      end
      body
    end

    def filename_for(uri, response, default_filename)
      name = File.basename(uri.path.to_s)
      name = default_filename if name.blank? || name == "/"

      # Ensure a sensible extension for images when the URL has none.
      if File.extname(name).blank?
        ext = MIME_EXTENSIONS[response["Content-Type"].to_s.split(";").first]
        name = "#{name}#{ext}" if ext
      end
      name
    end

    MIME_EXTENSIONS = {
      "application/pdf" => ".pdf",
      "image/jpeg" => ".jpg",
      "image/png" => ".png",
      "image/gif" => ".gif",
      "image/webp" => ".webp"
    }.freeze
  end
end

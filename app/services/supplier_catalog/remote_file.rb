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

    def public_ip?(address)
      ip = IPAddr.new(address)
      return false if ip.loopback? || ip.link_local? || ip.private?
      return false if ip.to_s == "0.0.0.0" || ip.to_s == "::"

      # Carrier-grade NAT (100.64.0.0/10) and IPv4-mapped ranges aren't covered
      # by IPAddr#private? — reject them explicitly.
      return false if ip.ipv4? && IPAddr.new("100.64.0.0/10").include?(ip)

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
      ip = validated_ip(uri.host)
      return nil unless ip

      http = Net::HTTP.new(uri.host, uri.port)
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

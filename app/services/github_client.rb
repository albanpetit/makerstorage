# frozen_string_literal: true

require "net/http"
require "openssl"

# The few GitHub REST calls a linked project needs: resolving a branch, tag or
# commit to a commit SHA, and downloading the repository at that commit as a
# ZIP. Only api.github.com and codeload.github.com (where archive downloads
# redirect) are ever contacted, so no user-supplied host is fetched.
#
#   client = GithubClient.new(token: organization.github_token)
#   sha = client.commit_sha("owner/board", "main")
#   client.download_archive("owner/board", sha) { |path| ... }
#
# Public repositories work without a token (GitHub then allows 60 requests an
# hour per IP); private ones need a token that can read the repository's
# contents.
class GithubClient
  API_HOST = "api.github.com"
  ARCHIVE_HOSTS = %w[codeload.github.com].freeze
  MAX_ARCHIVE_SIZE = 200.megabytes

  # The request failed: the message is shown to the user.
  class Error < StandardError; end

  NETWORK_ERRORS = SupplierCatalog::NETWORK_ERRORS

  # "owner/name", what a GitHub repository URL or path reduces to.
  REPOSITORY_FORMAT = %r{\A[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}\z}

  # Splits what a user pastes into { repository:, ref:, path: }: "owner/name",
  # or a github.com URL, including a ".../tree/<ref>/<folder>" or
  # ".../blob/<ref>/<folder>/<file>" one (the ref is taken to be one segment;
  # pick a branch with a slash in its name from the branch field instead).
  # Returns nil when +input+ names no repository.
  def self.parse(input)
    text = input.to_s.strip.sub(/\Agit@github\.com:/i, "").sub(%r{\A(https?://)?(www\.)?github\.com/}i, "")
    segments = text.split(/[?#]/).first.to_s.split("/").reject(&:blank?)
    return nil if segments.size < 2

    repository = "#{segments[0]}/#{segments[1].delete_suffix('.git')}"
    return nil unless repository.match?(REPOSITORY_FORMAT)

    ref = path = nil
    if %w[tree blob].include?(segments[2]) && segments[3]
      ref = segments[3]
      rest = segments[4..]
      rest = rest[0...-1] if segments[2] == "blob"
      path = rest.join("/").presence
    end
    { repository: repository, ref: ref, path: path }
  end

  def initialize(token: nil)
    @token = token.presence
  end

  # The commit SHA +ref+ (a branch, tag or commit; blank = the default branch)
  # points to.
  def commit_sha(repository, ref)
    path = "/repos/#{repository}/commits/#{escape(ref.presence || 'HEAD')}"
    response = request(URI::HTTPS.build(host: API_HOST, path: path), accept: "application/vnd.github.sha")
    check!(response, repository, ref)
    sha = response.body.to_s.strip
    raise Error, I18n.t("errors.github.unexpected_answer", repository: repository) unless sha.match?(/\A\h{40}\z/)

    sha
  end

  # Downloads +repository+ at +sha+ as a ZIP into a temporary file and yields
  # its path; the file is deleted afterwards.
  def download_archive(repository, sha)
    file = Tempfile.new([ "github", ".zip" ], binmode: true)
    uri = URI::HTTPS.build(host: API_HOST, path: "/repos/#{repository}/zipball/#{sha}")
    fetch_archive(uri, file, repository)
    file.flush
    yield file.path
  ensure
    file&.close!
  end

  private

  def escape(segment)
    URI.encode_www_form_component(segment).gsub("%2F", "/")
  end

  # Isolated HTTP boundary — stubbed in tests. Returns the Net::HTTPResponse
  # (body read) for a GET of +uri+.
  def request(uri, accept:)
    http(uri).request(get(uri, accept: accept))
  rescue *NETWORK_ERRORS => e
    raise Error, I18n.t("errors.github.unreachable", error: e.message)
  end

  # Streams the archive into +file+: the API answers with a redirect to
  # codeload.github.com, which is followed.
  def fetch_archive(uri, file, repository, redirects: 2)
    location = nil
    http(uri).request(get(uri, accept: "application/vnd.github+json")) do |response|
      if response.is_a?(Net::HTTPRedirection)
        location = URI(response["location"].to_s)
        next
      end

      check!(response, repository, nil)
      size = 0
      response.read_body do |chunk|
        size += chunk.bytesize
        raise Error, I18n.t("errors.github.too_large", repository: repository, size: ActiveSupport::NumberHelper.number_to_human_size(MAX_ARCHIVE_SIZE)) if size > MAX_ARCHIVE_SIZE

        file.write(chunk)
      end
    end
    return unless location

    unless redirects.positive? && location.is_a?(URI::HTTPS) && ARCHIVE_HOSTS.include?(location.host)
      raise Error, I18n.t("errors.github.unexpected_redirect")
    end
    fetch_archive(location, file, repository, redirects: redirects - 1)
  rescue *NETWORK_ERRORS, URI::InvalidURIError => e
    raise Error, I18n.t("errors.github.unreachable", error: e.message)
  end

  def http(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 30
    end
  end

  def get(uri, accept:)
    Net::HTTP::Get.new(uri).tap do |request|
      request["Accept"] = accept
      request["User-Agent"] = "MakerStorage"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      # Archive redirects carry their own short-lived token: ours stays on the API.
      request["Authorization"] = "Bearer #{@token}" if @token && uri.host == API_HOST
    end
  end

  def check!(response, repository, ref)
    return if response.is_a?(Net::HTTPSuccess)

    message =
      case response.code.to_i
      when 401
        I18n.t("errors.github.token_rejected")
      when 403, 429
        if response["x-ratelimit-remaining"] == "0" || response.code.to_i == 429
          I18n.t(@token ? "errors.github.rate_limited" : "errors.github.rate_limited_without_token")
        else
          I18n.t(@token ? "errors.github.forbidden_with_token" : "errors.github.forbidden", repository: repository)
        end
      when 404, 422
        if ref.present?
          I18n.t("errors.github.ref_not_found", repository: repository, ref: ref, hint: private_hint)
        else
          I18n.t("errors.github.not_found", repository: repository, hint: private_hint)
        end
      else
        I18n.t("errors.github.status", code: response.code, repository: repository)
      end
    raise Error, message
  end

  def private_hint
    @token ? "" : " #{I18n.t('errors.github.private_hint')}"
  end
end

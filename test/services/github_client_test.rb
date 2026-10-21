require "test_helper"

class GithubClientTest < ActiveSupport::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"

  # Answers Net::HTTP requests from a list of responses, in order, recording
  # the requests.
  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(request)
      @requests << request
      response = @responses.shift
      block_given? ? yield(response) : response
    end
  end

  test "parse takes owner/name and github.com URLs, with their branch and folder" do
    assert_equal({ repository: "maker/rover", ref: nil, path: nil }, GithubClient.parse("maker/rover"))
    assert_equal({ repository: "maker/rover", ref: nil, path: nil }, GithubClient.parse(" https://github.com/maker/rover.git "))
    assert_equal({ repository: "maker/rover", ref: nil, path: nil }, GithubClient.parse("git@github.com:maker/rover.git"))
    assert_equal({ repository: "maker/rover", ref: "v2", path: "hw/main" }, GithubClient.parse("https://github.com/maker/rover/tree/v2/hw/main"))
    assert_equal({ repository: "maker/rover", ref: "main", path: "hw" }, GithubClient.parse("github.com/maker/rover/blob/main/hw/board.kicad_pro?plain=1"))
    assert_nil GithubClient.parse("rover")
    assert_nil GithubClient.parse("https://github.com/maker/ro ver")
  end

  test "commit_sha asks for the ref's SHA, with the token when there is one" do
    http = FakeHttp.new([ response(Net::HTTPOK, 200, "#{SHA}\n") ])
    client = client_with(http, token: "ghp_secret")

    assert_equal SHA, client.commit_sha("maker/rover", "release/v2")
    request = http.requests.sole
    assert_equal "/repos/maker/rover/commits/release/v2", request.path
    assert_equal "application/vnd.github.sha", request["Accept"]
    assert_equal "Bearer ghp_secret", request["Authorization"]
  end

  test "commit_sha resolves the default branch as HEAD, without a token" do
    http = FakeHttp.new([ response(Net::HTTPOK, 200, SHA) ])

    assert_equal SHA, client_with(http).commit_sha("maker/rover", nil)
    assert_equal "/repos/maker/rover/commits/HEAD", http.requests.sole.path
    assert_nil http.requests.sole["Authorization"]
  end

  test "commit_sha explains GitHub's errors" do
    error = assert_raises(GithubClient::Error) { client_with(FakeHttp.new([ response(Net::HTTPNotFound, 404) ])).commit_sha("maker/rover", nil) }
    assert_match(/Could not find maker\/rover on GitHub \(a private repository needs a GitHub token/, error.message)

    error = assert_raises(GithubClient::Error) { client_with(FakeHttp.new([ response(Net::HTTPUnprocessableEntity, 422) ]), token: "t").commit_sha("maker/rover", "nope") }
    assert_equal "Could not find maker/rover at “nope” on GitHub. Check the repository and the branch, tag or commit.", error.message

    error = assert_raises(GithubClient::Error) { client_with(FakeHttp.new([ response(Net::HTTPUnauthorized, 401) ]), token: "t").commit_sha("maker/rover", nil) }
    assert_match(/rejected the token/, error.message)

    limited = response(Net::HTTPForbidden, 403).tap { |r| r["x-ratelimit-remaining"] = "0" }
    error = assert_raises(GithubClient::Error) { client_with(FakeHttp.new([ limited ])).commit_sha("maker/rover", nil) }
    assert_match(/rate limit is reached \(60 requests an hour without a token/, error.message)
  end

  test "download_archive follows the redirect to codeload and yields the ZIP" do
    redirect = response(Net::HTTPFound, 302).tap { |r| r["location"] = "https://codeload.github.com/maker/rover/legacy.zip/#{SHA}" }
    http = FakeHttp.new([ redirect, response(Net::HTTPOK, 200, "PK-zip") ])
    client = client_with(http, token: "ghp_secret")

    content = client.download_archive("maker/rover", SHA) { |path| File.binread(path) }

    assert_equal "PK-zip", content
    assert_equal [ "/repos/maker/rover/zipball/#{SHA}", "/maker/rover/legacy.zip/#{SHA}" ], http.requests.map(&:path)
    assert_equal [ "Bearer ghp_secret", nil ], http.requests.map { |request| request["Authorization"] }
  end

  test "download_archive refuses a redirect to another host" do
    redirect = response(Net::HTTPFound, 302).tap { |r| r["location"] = "https://example.com/evil.zip" }
    client = client_with(FakeHttp.new([ redirect ]))

    error = assert_raises(GithubClient::Error) { client.download_archive("maker/rover", SHA) { flunk } }
    assert_match(/somewhere unexpected/, error.message)
  end

  test "network failures become errors" do
    client = GithubClient.new
    client.define_singleton_method(:http) { |_uri| raise SocketError, "getaddrinfo failed" }

    error = assert_raises(GithubClient::Error) { client.commit_sha("maker/rover", nil) }
    assert_equal "Could not reach GitHub: getaddrinfo failed", error.message
  end

  private

  def client_with(http, token: nil)
    GithubClient.new(token: token).tap { |client| client.define_singleton_method(:http) { |_uri| http } }
  end

  def response(klass, code, body = "")
    klass.new("1.1", code.to_s, "").tap do |r|
      r.instance_variable_set(:@body, body)
      r.instance_variable_set(:@read, true)
      r.define_singleton_method(:read_body) { |&block| block ? block.call(body) : body }
    end
  end
end

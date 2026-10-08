require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "pages send the policy in report-only mode" do
    sign_in create_user
    get root_path

    assert_nil response.headers["Content-Security-Policy"], "not enforced yet"
    policy = response.headers["Content-Security-Policy-Report-Only"]
    assert_match(/default-src 'self'/, policy)
    assert_match(/object-src 'none'/, policy)
    assert_match(/frame-ancestors 'none'/, policy)
    # Part#image_source_url accepts http and https hotlinks; both must load.
    assert_match(/img-src [^;]*https:/, policy)
    assert_match(/img-src [^;]*http:(?!\/)/, policy)
  end

  test "the layout's inline theme script carries the nonce the policy allows" do
    sign_in create_user
    get root_path

    nonce = response.headers["Content-Security-Policy-Report-Only"][/'nonce-([^']+)'/, 1]
    assert nonce.present?
    assert_includes response.body, %(<script nonce="#{nonce}">)
  end

  test "the policy sends violation reports to the app" do
    sign_in create_user
    get root_path

    assert_match(%r{report-uri /csp-violations}, response.headers["Content-Security-Policy-Report-Only"])
  end

  test "a violation report is logged without a session or CSRF token" do
    report = { "csp-report" => { "violated-directive" => "script-src", "blocked-uri" => "https://evil.example/x.js", "document-uri" => "http://localhost/parts" } }

    logged = capture_log do
      post csp_reports_path, params: report.to_json, headers: { "Content-Type" => "application/csp-report" }
    end

    assert_response :no_content
    assert_match %r{\[CSP\] script-src blocked https://evil\.example/x\.js on http://localhost/parts}, logged
  end

  test "Reporting API reports are logged too" do
    report = [ { "type" => "csp-violation", "body" => { "effectiveDirective" => "img-src", "blockedURL" => "data", "documentURL" => "http://localhost/" } } ]

    logged = capture_log do
      post csp_reports_path, params: report.to_json, headers: { "Content-Type" => "application/reports+json" }
    end

    assert_match(/\[CSP\] img-src blocked data on/, logged)
  end

  test "malformed reports are ignored" do
    post csp_reports_path, params: "not json", headers: { "Content-Type" => "application/csp-report" }
    assert_response :no_content
  end

  test "reports are throttled per client" do
    CspReportsController::RATE_LIMIT.times { post csp_reports_path, params: "{}" }
    post csp_reports_path, params: "{}"

    assert_response :too_many_requests
  end

  private

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end

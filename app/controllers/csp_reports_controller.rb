# frozen_string_literal: true

# Receives the browser's Content-Security-Policy violation reports (the policy
# ships report-only, see config/initializers/content_security_policy.rb) and
# logs them, so what an enforced policy would break shows up in the logs before
# it's switched on. Browsers post these without a CSRF token or session, from
# any page, so the endpoint takes no action beyond a capped, throttled log line.
class CspReportsController < ActionController::Base
  MAX_BODY_BYTES = 8.kilobytes
  RATE_LIMIT = 30

  skip_forgery_protection
  rate_limit to: RATE_LIMIT, within: 1.minute, store: ApplicationController::AUTH_RATE_LIMIT_STORE,
             with: -> { head :too_many_requests }

  def create
    report = parse_report(request.body.read(MAX_BODY_BYTES).to_s)
    if report
      Rails.logger.warn(
        "[CSP] #{report['violated-directive'] || report['effectiveDirective']} blocked " \
        "#{report['blocked-uri'] || report['blockedURL']} on #{report['document-uri'] || report['documentURL']}"
      )
    end
    head :no_content
  end

  private

  # Handles both the report-uri format ({"csp-report": {...}}) and the Reporting
  # API's ([{"type": "csp-violation", "body": {...}}]). Values are truncated so a
  # crafted report can't flood the log.
  def parse_report(body)
    data = JSON.parse(body)
    report = data.is_a?(Array) ? data.first&.dig("body") : data["csp-report"]
    return nil unless report.is_a?(Hash)

    report.transform_values { |value| value.to_s.truncate(200) }
  rescue JSON::ParserError
    nil
  end
end

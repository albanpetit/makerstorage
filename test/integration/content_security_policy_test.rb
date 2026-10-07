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
end

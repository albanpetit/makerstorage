require "test_helper"

# Action Mailbox and Action Text aren't loaded (see config/application.rb), so
# their public ingress endpoints must not exist.
class UnusedFrameworkRoutesTest < ActionDispatch::IntegrationTest
  test "action mailbox ingresses are not routed" do
    post "/rails/action_mailbox/relay/inbound_emails"
    assert_response :not_found

    post "/rails/action_mailbox/mandrill/inbound_emails"
    assert_response :not_found
  end
end

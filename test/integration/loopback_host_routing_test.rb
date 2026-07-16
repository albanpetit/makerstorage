require "test_helper"

# The 127.0.0.1 → localhost redirect in config/routes.rb is a Vite dev-server
# convenience and must stay development-only: Capybara serves system tests on
# 127.0.0.1, and the cross-origin hop makes Chrome block every Inertia XHR
# with CORS errors (post-login navigation silently dies on /login).
class LoopbackHostRoutingTest < ActionDispatch::IntegrationTest
  test "requests to 127.0.0.1 are served directly, not redirected to localhost" do
    user = create_user
    sign_in user

    host! "127.0.0.1"
    get root_path

    assert_response :success
  end
end

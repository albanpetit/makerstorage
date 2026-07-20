require "test_helper"

# The scanner needs a camera, so this case runs Chrome with a synthetic media
# device (`--use-fake-device-for-media-stream`) and auto-grants the permission
# prompt. It verifies the camera starts and the decode path initialises without
# error; real QR *detection* can't be automated here (the Selenium browser runs
# in a separate container with no way to feed it a QR video).
class ScannerCameraTest < ActionDispatch::SystemTestCase
  FAKE_MEDIA_ARGS = %w[--use-fake-device-for-media-stream --use-fake-ui-for-media-stream].freeze

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    } do |opts|
      opts.add_argument("--unsafely-treat-insecure-origin-as-secure=http://rails-app:#{ENV["CAPYBARA_SERVER_PORT"]}")
      FAKE_MEDIA_ARGS.each { |arg| opts.add_argument(arg) }
    end
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |opts|
      FAKE_MEDIA_ARGS.each { |arg| opts.add_argument(arg) }
    end
  end

  setup do
    @user = create_user
    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "starting the camera activates the scanner without error" do
    visit scan_path
    assert_selector "h1", text: "Scanner", wait: 10

    click_on "Start camera"

    # The camera went live: the Stop control appears and no error banner shows.
    assert_selector "button", text: "Stop", wait: 10
    assert_no_text "Could not start the camera"
    assert_no_text "does not support camera access"
  end
end

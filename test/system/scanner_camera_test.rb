require "test_helper"

# The scanner needs a camera, so this case runs Chrome with a synthetic media
# device (`--use-fake-device-for-media-stream`) and auto-grants the permission
# prompt. Locally, the fake camera films a QR label (QR_VIDEO, written below):
# headless Chrome on Linux has no BarcodeDetector, so this reads it through
# the ZXing fallback, the one Safari and Firefox use. A remote Selenium
# browser (in another container) can't be fed that file: there the test only
# checks the camera starts.
class ScannerCameraTest < ActionDispatch::SystemTestCase
  FAKE_MEDIA_ARGS = %w[--use-fake-device-for-media-stream --use-fake-ui-for-media-stream].freeze
  QR_CODE = "MS-04242"
  QR_VIDEO = Rails.root.join("tmp/test-camera-qr.y4m")

  # A still 1280x720 Y4M clip of a printed label's QR code (a link to the
  # Scanner page, as labels print it), small in the frame like a label held
  # at arm's length. The QR matrix comes from the same ZXing the app prints with.
  def self.write_qr_video
    script = "const z = require('@zxing/library'); const m = z.QRCodeEncoder.encode(process.argv[1], z.QRCodeDecoderErrorCorrectionLevel.M).getMatrix();" \
             "const rows = []; for (let y = 0; y < m.getHeight(); y++) { let r = ''; for (let x = 0; x < m.getWidth(); x++) r += m.get(x, y) ? '1' : '0'; rows.push(r) } console.log(rows.join('\\n'))"
    rows = IO.popen([ "node", "-e", script, "http://127.0.0.1/scan?code=#{QR_CODE}" ], chdir: Rails.root, &:read).split
    return false if rows.empty?

    width, height, module_px = 1280, 720, 3
    luma = Array.new(height) { "\xC8".b * width }
    size = (rows.size + 8) * module_px
    left, top = (width - size) / 2, (height - size) / 2
    size.times do |y|
      line = luma[top + y]
      size.times do |x|
        row = rows[(y / module_px) - 4]
        dark = row && (y / module_px) >= 4 && (x / module_px) >= 4 && row[(x / module_px) - 4] == "1"
        line.setbyte(left + x, dark ? 30 : 235)
      end
    end
    frame = "FRAME\n".b + luma.join + ("\x80".b * (width * height / 2))
    File.binwrite(QR_VIDEO, "YUV4MPEG2 W#{width} H#{height} F30:1 Ip A1:1 C420jpeg\n".b + frame + frame)
    true
  rescue SystemCallError
    false
  end

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444",
      name: :fake_camera_chrome
    } do |opts|
      opts.add_argument("--unsafely-treat-insecure-origin-as-secure=http://rails-app:#{ENV["CAPYBARA_SERVER_PORT"]}")
      FAKE_MEDIA_ARGS.each { |arg| opts.add_argument(arg) }
    end
  else
    QR_VIDEO_READY = write_qr_video

    # A driver (and so a browser) of its own: Capybara keeps one browser per
    # driver name, and the other system tests' browser has no fake camera.
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: { name: :fake_camera_chrome } do |opts|
      FAKE_MEDIA_ARGS.each { |arg| opts.add_argument(arg) }
      opts.add_argument("--use-file-for-fake-video-capture=#{QR_VIDEO}") if QR_VIDEO_READY
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

  test "the camera reads a label's QR code and opens its part" do
    skip "needs a local browser and Node" unless defined?(QR_VIDEO_READY) && QR_VIDEO_READY
    create_part(organization: @user.organizations.first, name: "Filmed part", ipn: QR_CODE)

    visit scan_path
    assert_selector "h1", text: "Scanner", wait: 10
    click_on "Start camera"

    assert_text "Filmed part", wait: 10
    assert_selector "button", text: "Start camera"
  end
end

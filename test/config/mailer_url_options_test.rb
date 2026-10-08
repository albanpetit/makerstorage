require "test_helper"

class MailerUrlOptionsTest < ActiveSupport::TestCase
  def with_env(vars)
    saved = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  test "email links use https when FORCE_SSL is on" do
    with_env("FORCE_SSL" => "true", "APP_PROTOCOL" => nil, "APP_HOST" => "parts.example.org") do
      assert_equal({ host: "parts.example.org", protocol: "https" }, Makerstorage.mailer_url_options_from_env)
    end
  end

  test "email links use plain http on installs without FORCE_SSL" do
    with_env("FORCE_SSL" => nil, "APP_PROTOCOL" => nil, "APP_HOST" => "192.168.1.20:3000") do
      assert_equal({ host: "192.168.1.20:3000", protocol: "http" }, Makerstorage.mailer_url_options_from_env)
    end
  end

  test "APP_PROTOCOL overrides the protocol, e.g. behind a TLS tunnel without FORCE_SSL" do
    with_env("FORCE_SSL" => nil, "APP_PROTOCOL" => "https", "APP_HOST" => "parts.example.org") do
      assert_equal "https", Makerstorage.mailer_url_options_from_env[:protocol]
    end
  end

  test "an unknown APP_PROTOCOL falls back to the FORCE_SSL default" do
    with_env("FORCE_SSL" => nil, "APP_PROTOCOL" => "ftp") do
      assert_equal "http", Makerstorage.mailer_url_options_from_env[:protocol]
    end
  end

  test "FORCE_SSL accepts the usual truthy spellings only" do
    %w[1 true TRUE yes].each do |value|
      with_env("FORCE_SSL" => value) { assert Makerstorage.force_ssl_from_env?, value }
    end
    %w[0 false no].each do |value|
      with_env("FORCE_SSL" => value) { assert_not Makerstorage.force_ssl_from_env?, value }
    end
  end
end

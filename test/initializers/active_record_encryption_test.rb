# frozen_string_literal: true

require "test_helper"

# Guards config/initializers/active_record_encryption.rb. The image build precompiles
# assets by booting the *production* environment with SECRET_KEY_BASE_DUMMY set and no
# master key (config/master.key is dockerignored, so credentials are empty). The
# initializer must not hard-raise in that dummy boot, yet must still refuse to boot a
# real production process when encryption keys are genuinely missing.
class ActiveRecordEncryptionInitializerTest < ActiveSupport::TestCase
  # Boot a fresh Rails process in production and report [combined_output, success?].
  def boot_production(env)
    output = nil
    Dir.chdir(Rails.root) do
      IO.popen(env.merge("RAILS_ENV" => "production"),
               [ "bin/rails", "runner", "puts 'BOOT_OK'" ],
               err: [ :child, :out ]) { |io| output = io.read }
    end
    [ output, $?.success? ]
  end

  test "production asset precompile boots without encryption keys when SECRET_KEY_BASE_DUMMY is set" do
    output, ok = boot_production(
      "SECRET_KEY_BASE_DUMMY" => "1",
      "AR_ENCRYPTION_PRIMARY_KEY" => "",
      "AR_ENCRYPTION_DETERMINISTIC_KEY" => "",
      "AR_ENCRYPTION_KEY_DERIVATION_SALT" => ""
    )

    assert ok, "expected the dummy production boot to succeed, but it failed:\n#{output}"
    assert_match "BOOT_OK", output
  end

  test "real production boot refuses to start when encryption keys are missing" do
    # Only meaningful when credentials don't already supply the keys (e.g. CI, where
    # there is no master key). Locally the decrypted credentials provide them.
    if Rails.application.credentials.dig(:active_record_encryption, :primary_key).present?
      skip "credentials already provide encryption keys in this environment"
    end

    output, ok = boot_production(
      "SECRET_KEY_BASE" => "a" * 64,
      "AR_ENCRYPTION_PRIMARY_KEY" => "",
      "AR_ENCRYPTION_DETERMINISTIC_KEY" => "",
      "AR_ENCRYPTION_KEY_DERIVATION_SALT" => ""
    )

    refute ok, "expected production boot to fail without encryption keys, but it succeeded:\n#{output}"
    assert_match "Active Record Encryption keys are missing", output
  end
end

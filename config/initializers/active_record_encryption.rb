# frozen_string_literal: true

# Active Record Encryption keys. Used to encrypt sensitive per-organization
# secrets at rest (e.g. supplier API keys — see Organization#mouser_api_key).
#
# Key resolution order:
#   1. Encrypted credentials, under the `active_record_encryption:` key
#      (`bin/rails credentials:edit`) — the recommended home for real keys.
#   2. Environment variables (AR_ENCRYPTION_*) — handy for container deploys.
#   3. Fixed, non-secret development/test fallbacks so the app boots without
#      setup. These are NOT secret and must never be used in production.
Rails.application.configure do
  encryption = config.active_record.encryption
  credentials = Rails.application.credentials.active_record_encryption || {}

  primary_key = credentials[:primary_key] || ENV["AR_ENCRYPTION_PRIMARY_KEY"]
  deterministic_key = credentials[:deterministic_key] || ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
  key_derivation_salt = credentials[:key_derivation_salt] || ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]

  if Rails.env.production? && [ primary_key, deterministic_key, key_derivation_salt ].any?(&:blank?)
    raise "Active Record Encryption keys are missing. Set them in credentials " \
          "(active_record_encryption:) or the AR_ENCRYPTION_* environment variables."
  end

  encryption.primary_key = primary_key || "development_primary_key_do_not_use_in_prod"
  encryption.deterministic_key = deterministic_key || "development_deterministic_key_no_prod"
  encryption.key_derivation_salt = key_derivation_salt || "development_key_derivation_salt_no_prod"
end

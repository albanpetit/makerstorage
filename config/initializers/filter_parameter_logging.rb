# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Personal data typed for a loan, and OAuth codes (single use, but no reason
  # to keep them). /\Acode\z/ matches the bare "code" param only (OAuth, and
  # the scanner's), not zone or category codes.
  :borrower_contact, :borrower_name, :code_verifier, /\Acode\z/
]

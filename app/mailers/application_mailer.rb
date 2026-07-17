class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_SENDER", "Makerstorage <no-reply@example.com>")
  layout "mailer"
end

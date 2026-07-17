class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_SENDER", "Makerstorage <contact@makerstorage.io>")
  layout "mailer"
end

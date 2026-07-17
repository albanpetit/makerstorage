class ApplicationMailer < ActionMailer::Base
  default from: ENV["MAILER_SENDER"].presence || "Makerstorage <no-reply@example.com>"
  layout "mailer"
end

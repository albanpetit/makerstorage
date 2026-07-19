class ApplicationMailer < ActionMailer::Base
  default from: ENV["MAILER_SENDER"].presence || "Makerstorage <no-reply@example.com>"
  layout "mailer"

  before_action :attach_brand_logo

  private

  # Embed the logo as an inline CID attachment so it renders without depending
  # on a configured asset host or the client allowing remote images.
  def attach_brand_logo
    attachments.inline["logo.png"] = Rails.root.join("public/icon-180.png").read
  end
end

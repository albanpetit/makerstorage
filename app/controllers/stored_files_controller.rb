# frozen_string_literal: true

# Serves uploaded files (part images and datasheets, organization, supplier and
# footprint logos) to members of the organization that owns them. Active
# Storage's own blob routes answer anyone holding a link, forever — a member
# removed from an organization kept access to every file URL they had seen —
# so those routes are closed (config/routes.rb) and links point here instead.
class StoredFilesController < ApplicationController
  include Auth

  def show
    blob = ActiveStorage::Blob.find_signed(params[:signed_id])
    return head(:not_found) unless blob && readable?(blob)

    # Private: shared caches must not keep a member-only file.
    expires_in 1.hour, public: false

    if blob.content_type == SVG_TYPE
      send_svg(blob)
    else
      send_data blob.download,
        filename: blob.filename.sanitized,
        type: blob.content_type_for_serving,
        disposition: blob.forced_disposition_for_serving || params[:disposition].presence_in(%w[inline attachment]) || "inline"
    end
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end

  SVG_TYPE = "image/svg+xml"
  # Scripts, external loads, and forms are all off, so an SVG opened directly
  # (top-level, same origin) is inert; <img> never runs them anyway.
  SVG_POLICY = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox"

  private

  # Active Storage serves SVG as an octet-stream download (it can carry
  # script), which an <img> then refuses to draw — so SVG logos and footprint
  # drawings showed as broken images. Serve it as an image instead, locked down
  # by its own enforced CSP.
  def send_svg(blob)
    response.headers["Content-Security-Policy"] = SVG_POLICY
    send_data blob.download, filename: blob.filename.sanitized, type: SVG_TYPE, disposition: "inline"
  end

  def readable?(blob)
    organization_ids = current_user.organizations.ids
    blob.attachments.includes(:record).any? do |attachment|
      record = attachment.record
      owner_id = record.is_a?(Organization) ? record.id : record.try(:organization_id)
      organization_ids.include?(owner_id)
    end
  end
end

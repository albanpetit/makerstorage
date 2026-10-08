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
    send_data blob.download,
      filename: blob.filename.sanitized,
      type: blob.content_type_for_serving,
      disposition: blob.forced_disposition_for_serving || params[:disposition].presence_in(%w[inline attachment]) || "inline"
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end

  private

  def readable?(blob)
    organization_ids = current_user.organizations.ids
    blob.attachments.includes(:record).any? do |attachment|
      record = attachment.record
      owner_id = record.is_a?(Organization) ? record.id : record.try(:organization_id)
      organization_ids.include?(owner_id)
    end
  end
end

# frozen_string_literal: true

# A part's files (Part#attachments: application notes, 3D models, firmware…),
# added and removed from the part sheet. Removing also covers the datasheet a
# supplier lookup attached, which the sheet lists with them.
class PartAttachmentsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer
  before_action :set_part

  def create
    uploads = Array(params[:files]).select { |upload| upload.respond_to?(:original_filename) }
    return redirect_back_or_to(parts_path, alert: t("flash.part_attachments.choose_files")) if uploads.empty?

    if (error = upload_error(uploads))
      return redirect_back_or_to(parts_path, alert: error)
    end

    ActiveRecord::Base.transaction do
      @part.attachments.attach(uploads.map { |upload| attachable(upload) })
      @part.save!
    end
    redirect_back_or_to parts_path, notice: t("flash.part_attachments.added", count: uploads.size)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to parts_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    file = @part.attachments_attachments.find_by(id: params[:id]) ||
      (@part.datasheet_attachment if @part.datasheet_attachment&.id.to_s == params[:id].to_s)
    raise ActiveRecord::RecordNotFound unless file

    file.purge
    redirect_back_or_to parts_path, notice: t("flash.part_attachments.removed", name: file.filename.to_s)
  end

  private

  def set_part
    @part = current_organization.parts.find(params[:part_id])
  end

  # Checked before anything is stored, so a refused upload leaves no blob.
  def upload_error(uploads)
    if uploads.size + @part.attachments.size > Part::MAX_ATTACHMENTS
      t("flash.part_attachments.too_many", count: Part::MAX_ATTACHMENTS)
    elsif (large = uploads.find { |upload| upload.size > Part.attachment_limits["attachments"][:max_size] })
      t("flash.part_attachments.too_large", name: File.basename(large.original_filename.to_s),
        size: ActiveSupport::NumberHelper.number_to_human_size(Part.attachment_limits["attachments"][:max_size]))
    end
  end

  def attachable(upload)
    { io: File.open(upload.path, "rb"), filename: File.basename(upload.original_filename.to_s), content_type: upload.content_type }
  end
end

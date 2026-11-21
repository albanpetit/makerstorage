# Content-type and size limits for Active Storage attachments, so an upload
# can't fill the disk or smuggle in an unexpected file type.
#
#   validates_attachment :images, content_types: AttachmentValidation::IMAGE_TYPES, max_size: 10.megabytes
module AttachmentValidation
  extend ActiveSupport::Concern

  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  # Logos and footprint drawings are often vector art. SVG is safe here: it's
  # only shown through <img>, and StoredFilesController serves it under a
  # sandboxing CSP that keeps any embedded script inert.
  LOGO_TYPES = (IMAGE_TYPES + %w[image/svg+xml]).freeze
  PDF_TYPES = %w[application/pdf].freeze
  # Any file (part attachments: STEP models, firmware, app notes…). Safe to
  # serve: StoredFilesController sends what browsers can't show safely
  # inline (HTML, SVG, scripts) as a download.
  ANY_TYPE = :any

  included do
    # name => { content_types:, max_size: }, for code that attaches files
    # without going through the record's validation (organization backups).
    class_attribute :attachment_limits, instance_writer: false, default: {}.freeze
  end

  class_methods do
    def validates_attachment(name, content_types:, max_size:)
      self.attachment_limits = attachment_limits.merge(name.to_s => { content_types: content_types, max_size: max_size }).freeze

      validate do
        attached = public_send(name)
        next unless attached.attached?

        blobs = attached.respond_to?(:blobs) ? attached.blobs : [ attached.blob ]
        blobs.each do |blob|
          unless AttachmentValidation.allowed_type?(content_types, blob.content_type)
            errors.add(name, :attachment_type, types: AttachmentValidation.describe(content_types))
          end
          if blob.byte_size > max_size
            errors.add(name, :attachment_size, size: ActiveSupport::NumberHelper.number_to_human_size(max_size))
          end
        end

        # Files being added now (their blob isn't stored yet) must fit in what's
        # left of the organization's quota. Checked before upload, so a refused
        # file never reaches the disk.
        added = blobs.select(&:new_record?).sum(&:byte_size)
        organization = is_a?(Organization) ? self : try(:organization)
        if added.positive? && organization && !AttachmentValidation.fits_quota?(organization, added)
          errors.add(name, :storage_quota_exceeded, quota: ActiveSupport::NumberHelper.number_to_human_size(AttachmentValidation.quota))
        end
      end
    end
  end

  # Models whose files count against their organization's quota, with how
  # their rows tie to it.
  QUOTA_RECORDS = {
    "Organization" => :id, "Part" => :organization_id, "Project" => :organization_id,
    "Supplier" => :organization_id, "Footprint" => :organization_id
  }.freeze

  def self.quota
    Rails.configuration.x.organization_storage_quota
  end

  # Whether +bytes+ more still fit in +organization+'s quota (always, without one).
  def self.fits_quota?(organization, bytes)
    quota.nil? || storage_used(organization) + bytes <= quota
  end

  # Bytes of files held by +organization+'s records, each file once (a project
  # revision shares its files with the original).
  def self.storage_used(organization)
    scopes = QUOTA_RECORDS.map do |type, column|
      ids = type.constantize.where(column => organization.id).select(:id)
      ActiveStorage::Attachment.where(record_type: type, record_id: ids)
    end
    blob_ids = scopes.reduce { |all, scope| all.or(scope) }.select(:blob_id)
    ActiveStorage::Blob.where(id: blob_ids).sum(:byte_size)
  end

  def self.allowed_type?(content_types, content_type)
    content_types == ANY_TYPE || content_types.include?(content_type)
  end

  def self.describe(content_types)
    content_types.map { |type| type.split("/").last.delete_suffix("+xml").upcase }.to_sentence(last_word_connector: " or ", two_words_connector: " or ")
  end
end

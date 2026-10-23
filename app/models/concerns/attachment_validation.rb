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
      end
    end
  end

  def self.allowed_type?(content_types, content_type)
    content_types == ANY_TYPE || content_types.include?(content_type)
  end

  def self.describe(content_types)
    content_types.map { |type| type.split("/").last.delete_suffix("+xml").upcase }.to_sentence(last_word_connector: " or ", two_words_connector: " or ")
  end
end

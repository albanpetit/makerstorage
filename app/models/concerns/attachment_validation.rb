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

  class_methods do
    def validates_attachment(name, content_types:, max_size:)
      validate do
        attached = public_send(name)
        next unless attached.attached?

        blobs = attached.respond_to?(:blobs) ? attached.blobs : [ attached.blob ]
        blobs.each do |blob|
          unless content_types.include?(blob.content_type)
            errors.add(name, "must be a #{AttachmentValidation.describe(content_types)} file")
          end
          if blob.byte_size > max_size
            errors.add(name, "must be smaller than #{ActiveSupport::NumberHelper.number_to_human_size(max_size)}")
          end
        end
      end
    end
  end

  def self.describe(content_types)
    content_types.map { |type| type.split("/").last.delete_suffix("+xml").upcase }.to_sentence(last_word_connector: " or ", two_words_connector: " or ")
  end
end

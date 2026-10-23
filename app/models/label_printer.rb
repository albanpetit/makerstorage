# A label printer on the organization's local network that the server prints
# to directly (raw TCP, port 9100 by default). The browser renders each label
# as a 1-bit bitmap at the printer's exact size (#geometry) and the server
# wraps it in the printer's language and sends it (LabelPrinting).
class LabelPrinter < ApplicationRecord
  # Activity log (Auditable).
  audited

  PROTOCOLS = %w[brother_ql zpl].freeze
  MAX_LABEL_MM = 300

  belongs_to :organization

  validates :name, presence: true, length: { maximum: 60 }
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :host, presence: true, length: { maximum: 253 },
                   format: { with: /\A[a-zA-Z0-9.:\-\[\]]+\z/, message: "must be a host name or IP address" }
  validate :port_is_a_printer_port
  validates :media, inclusion: { in: LabelPrinting::BrotherQl::MEDIA.keys }, if: :brother_ql?
  validates :length_mm, numericality: { greater_than_or_equal_to: 10, less_than_or_equal_to: MAX_LABEL_MM },
                        if: -> { zpl? || brother_media&.continuous? }
  validates :width_mm, numericality: { greater_than_or_equal_to: 10, less_than_or_equal_to: 120 }, if: :zpl?
  validates :dpi, inclusion: { in: LabelPrinting::Zpl::DPIS }, if: :zpl?

  normalizes :host, with: ->(host) { host.strip.delete_prefix("[").delete_suffix("]") }

  scope :alphabetical, -> { order(:name) }

  def brother_ql? = protocol == "brother_ql"
  def zpl? = protocol == "zpl"

  def brother_media
    LabelPrinting::BrotherQl::MEDIA[media] if brother_ql?
  end

  # The bitmap the browser renders for one label: +width+ dots across the print
  # head by +height+ dots along the feed, at +dots_per_mm+.
  def geometry
    if brother_ql?
      media = brother_media
      { width: media.printable_width, height: LabelPrinting::BrotherQl.raster_lines(media, length_mm),
        dots_per_mm: LabelPrinting::BrotherQl::DOTS_PER_MM }
    else
      { width: LabelPrinting::Zpl.dots(width_mm, dpi), height: LabelPrinting::Zpl.dots(length_mm, dpi), dots_per_mm: dpi / 25.4 }
    end
  end

  # "62 × 29 mm" as printed (Brother continuous rolls: the chosen length).
  def size_label
    if brother_ql?
      media = brother_media
      "#{media.width_mm} × #{format_mm(media.length_mm || length_mm)} mm"
    else
      "#{format_mm(width_mm)} × #{format_mm(length_mm)} mm"
    end
  end

  # Byte size of one packed bitmap at #geometry.
  def bitmap_bytesize
    size = geometry
    ((size[:width] + 7) / 8) * size[:height]
  end

  # Sends +bitmaps+ (packed 1-bit images at #geometry) to the printer. Raises
  # LabelPrinting::Network::Error when the printer can't be reached.
  def print_bitmaps(bitmaps)
    size = geometry
    job = if brother_ql?
      LabelPrinting::BrotherQl.encode(bitmaps, media: brother_media, lines: size[:height])
    else
      LabelPrinting::Zpl.encode(bitmaps, width: size[:width], height: size[:height])
    end
    LabelPrinting::Network.deliver(host, port, job)
  end

  private

  def port_is_a_printer_port
    return if LabelPrinting::Network.allowed_port?(port)

    errors.add(:port, :printer_port)
  end

  def format_mm(value)
    value.to_f == value.to_i ? value.to_i.to_s : value.to_f.round(1).to_s
  end
end

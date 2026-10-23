# AI-assisted part entry: sends photos of a component (its reel or bag label,
# the part itself) and/or its datasheet PDF to Claude with the organization's
# own Anthropic API key, and reads back the part's details as the add-part form
# fills them in.
#
# The organization's categories, footprints and parameter definitions go along
# with the files so Claude can pick from them; the ids it returns are checked
# against the organization and dropped if they aren't its own. Nothing is
# saved here: the form shows the result for the user to review.
#
# Opt-in per organization (Settings → Integrations): off until an admin saves
# an API key, which is encrypted, write-only and left out of backups.
class PartExtraction
  class Error < StandardError; end
  class NotConfiguredError < Error; end
  class InvalidFileError < Error; end

  # Models an organization can choose (value: the label shown in Settings).
  MODELS = {
    "claude-opus-5-5" => "Claude Opus 5.5",
    "claude-sonnet-5-5" => "Claude Sonnet 5.5",
    "claude-haiku-5-5" => "Claude Haiku 5.5"
  }.freeze
  DEFAULT_MODEL = "claude-opus-5-5"

  IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  PDF_TYPE = "application/pdf"
  # The API's own limits: 5 MB per image, 32 MB per request (PDFs included).
  MAX_IMAGE_SIZE = 5.megabytes
  MAX_PDF_SIZE = 25.megabytes
  MAX_FILES = 4
  MAX_HINT_LENGTH = 500

  # A datasheet read can take a while; the add-part dialog waits for it.
  TIMEOUT = 120
  MAX_TOKENS = 16_000

  TEXT_FIELDS = %w[name mpn manufacturer description value package_type tolerance voltage_rating power_rating].freeze
  FIELD_LIMITS = { "description" => 2000 }.freeze
  DEFAULT_FIELD_LIMIT = 255

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You fill in an electronics inventory's "add part" form from photos and datasheets that a
    makerspace member provides: a component, its reel or bag label, or its datasheet PDF.

    Report only what the files show or what follows directly from them (a resistor's colour bands,
    a datasheet's ordering information). Leave a field null when you can't tell; a wrong value is
    worse than an empty one, because the member trusts the form.

    - name: a short, searchable inventory name, e.g. "Resistor 10k 1% 0603" or "ATmega328P-AU MCU".
    - mpn: the exact manufacturer part number, with its ordering suffix when it is visible.
    - value: the main electrical value in the usual notation ("10k", "100nF", "4.7uH"), null for ICs.
    - package_type: the package as written by the manufacturer ("0603", "SOIC-8", "TO-220").
    - tolerance, voltage_rating, power_rating: as printed ("1%", "50V", "0.1W").
    - category_id, footprint_id: an id from the lists given, or null when none fits.
    - parameters: values for the parameter definitions given (by id), typed with their unit or a
      prefix ("4k7", "100nF", "3V3"); only those you can read, none invented.
    - quantity: the number of pieces when a bag or reel label states it, else null.
    - rohs_compliant: true only when the files say so.
    - notes: one or two short sentences on anything uncertain the member should check, else null.
    Write the name, description and notes in the language asked for in the request.
  PROMPT

  def self.available?(organization)
    organization.ai_entry_configured?
  end

  def self.model_label(model)
    MODELS.fetch(model, model)
  end

  def initialize(organization, client: nil)
    @organization = organization
    @client = client
  end

  # +files+: uploaded files (ActionDispatch::Http::UploadedFile or anything
  # with #read, #size, #content_type, #original_filename). +hint+: optional
  # text from the user ("10k pull-ups from the red drawer"). Returns a Hash
  # ready for the form (see #normalize). Raises Error subclasses with a
  # translated message.
  def extract(files, hint: nil)
    raise NotConfiguredError, I18n.t("errors.ai_entry.not_configured") unless self.class.available?(@organization)

    files = Array(files).compact_blank
    raise InvalidFileError, I18n.t("errors.ai_entry.no_file") if files.empty?
    raise InvalidFileError, I18n.t("errors.ai_entry.too_many_files", count: MAX_FILES) if files.size > MAX_FILES

    message = client.messages.create(
      model: @organization.ai_model,
      max_tokens: MAX_TOKENS,
      system_: SYSTEM_PROMPT,
      output_config: { effort: :medium, format_: { type: :json_schema, schema: output_schema } },
      messages: [ { role: "user", content: files.map { |file| content_block(file) } + [ { type: "text", text: request_text(hint) } ] } ],
      request_options: { timeout: TIMEOUT, max_retries: 1 }
    )
    normalize(parse(message))
  rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError
    raise Error, I18n.t("errors.ai_entry.key_refused")
  rescue Anthropic::Errors::RateLimitError
    raise Error, I18n.t("errors.ai_entry.rate_limited")
  rescue Anthropic::Errors::BadRequestError => e
    Rails.logger.warn("[PartExtraction] request refused: #{e.message}")
    raise Error, I18n.t("errors.ai_entry.request_refused")
  rescue Anthropic::Errors::APIStatusError, Anthropic::Errors::APIConnectionError => e
    Rails.logger.warn("[PartExtraction] #{e.class}: #{e.message}")
    raise Error, I18n.t("errors.ai_entry.unreachable")
  end

  private

  def client
    @client ||= Anthropic::Client.new(api_key: @organization.anthropic_api_key)
  end

  def content_block(file)
    type = file.content_type.to_s.split(";").first.to_s.strip.downcase
    data = Base64.strict_encode64(read_checked(file, type))
    if type == PDF_TYPE
      { type: "document", source: { type: "base64", media_type: PDF_TYPE, data: data } }
    else
      { type: "image", source: { type: "base64", media_type: type, data: data } }
    end
  end

  def read_checked(file, type)
    name = file.original_filename.to_s
    limit = if type == PDF_TYPE then MAX_PDF_SIZE
    elsif IMAGE_TYPES.include?(type) then MAX_IMAGE_SIZE
    else raise InvalidFileError, I18n.t("errors.ai_entry.unsupported_file", name: name)
    end
    if file.size > limit
      raise InvalidFileError, I18n.t("errors.ai_entry.file_too_large", name: name, size: ActiveSupport::NumberHelper.number_to_human_size(limit))
    end

    data = file.read
    file.rewind if file.respond_to?(:rewind)
    # Don't trust the browser's type: a PDF starts with %PDF, images with
    # their own magic bytes.
    raise InvalidFileError, I18n.t("errors.ai_entry.unsupported_file", name: name) unless content_matches?(data, type)

    data
  end

  def content_matches?(data, type)
    head = data.byteslice(0, 12).to_s.b
    case type
    when PDF_TYPE then head.start_with?("%PDF")
    when "image/jpeg" then head.start_with?("\xFF\xD8\xFF".b)
    when "image/png" then head.start_with?("\x89PNG".b)
    when "image/gif" then head.start_with?("GIF8")
    when "image/webp" then head.start_with?("RIFF") && head.byteslice(8, 4) == "WEBP"
    else false
    end
  end

  # The organization's own vocabulary, so Claude picks existing records.
  def request_text(hint)
    cache = Category.full_path_cache(@organization.categories)
    context = {
      language: I18n.locale.to_s == "fr" ? "French" : "English",
      categories: cache.values.map { |category| { id: category.id, path: category.full_path(cache: cache) } }.sort_by { |c| c[:path] },
      footprints: @organization.footprints.order(:name).map { |footprint| { id: footprint.id, name: footprint.name } },
      parameters: @organization.parameter_definitions.order(:name).map do |definition|
        { id: definition.id, name: definition.name, type: definition.value_type, unit: definition.unit.presence }.compact
      end
    }
    text = "Fill in the part form from the attached file(s).\n\n#{JSON.generate(context)}"
    hint = hint.to_s.strip.first(MAX_HINT_LENGTH)
    hint.present? ? "#{text}\n\nThe member adds: #{hint}" : text
  end

  def output_schema
    nullable_string = { type: %w[string null] }
    nullable_integer = { type: %w[integer null] }
    properties = TEXT_FIELDS.index_with { nullable_string }.merge(
      "category_id" => nullable_integer,
      "footprint_id" => nullable_integer,
      "quantity" => nullable_integer,
      "rohs_compliant" => { type: %w[boolean null] },
      "notes" => nullable_string,
      "parameters" => {
        type: "array",
        items: {
          type: "object",
          properties: { "definition_id" => { type: "integer" }, "value" => { type: "string" } },
          required: %w[definition_id value],
          additionalProperties: false
        }
      }
    )
    { type: "object", properties: properties, required: properties.keys, additionalProperties: false }
  end

  def parse(message)
    raise Error, I18n.t("errors.ai_entry.declined") if message.stop_reason == :refusal

    text = message.content.select { |block| block.type == :text }.map(&:text).join
    JSON.parse(text)
  rescue JSON::ParserError
    raise Error, I18n.t("errors.ai_entry.unreadable")
  end

  # Strings trimmed and capped, ids kept only when they're this
  # organization's, parameters keyed by definition id like the part form.
  def normalize(raw)
    raw = {} unless raw.is_a?(Hash)
    fields = TEXT_FIELDS.index_with do |field|
      value = raw[field]
      value.is_a?(String) ? value.strip.first(FIELD_LIMITS.fetch(field, DEFAULT_FIELD_LIMIT)).presence : nil
    end

    category_id = owned_id(@organization.categories, raw["category_id"])
    footprint_id = owned_id(@organization.footprints, raw["footprint_id"])
    definitions = @organization.parameter_definitions.pluck(:id).to_set
    parameters = Array(raw["parameters"]).each_with_object({}) do |entry, values|
      next unless entry.is_a?(Hash) && definitions.include?(entry["definition_id"])

      value = entry["value"].to_s.strip.first(DEFAULT_FIELD_LIMIT)
      values[entry["definition_id"].to_s] = value if value.present?
    end
    quantity = raw["quantity"]
    quantity = nil unless quantity.is_a?(Integer) && quantity.positive?
    existing = fields["mpn"] && @organization.parts.where("LOWER(mpn) = ?", fields["mpn"].downcase).pick(:id, :name)

    fields.merge(
      "category_id" => category_id,
      "footprint_id" => footprint_id,
      "parameters" => parameters,
      "quantity" => quantity,
      "rohs_compliant" => raw["rohs_compliant"] == true,
      "notes" => raw["notes"].is_a?(String) ? raw["notes"].strip.first(500).presence : nil,
      "existing_part" => existing && { "id" => existing[0], "name" => existing[1] }
    )
  end

  def owned_id(scope, id)
    id.is_a?(Integer) && scope.exists?(id: id) ? id : nil
  end
end

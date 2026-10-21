# frozen_string_literal: true

# KiCad HTTP library (https://docs.kicad.org/9.0/en/eeschema/eeschema_advanced.html#http-libraries):
# exposes an organization's parts to KiCad's symbol chooser, each one a KiCad
# symbol (from the user's own libraries) with MakerStorage's fields filled in.
#
# KiCad reads a `.kicad_httplib` file holding the root URL and a token, then
# calls, with `Authorization: Token <token>`:
#   GET <root>/v1/                          endpoint check
#   GET <root>/v1/categories.json           [{ id, name, description }]
#   GET <root>/v1/parts/category/<id>.json  [{ id, name, description }]
#   GET <root>/v1/parts/<id>.json           the part's symbol and fields
# Every id and value is a string, booleans included ("True"/"False").
#
# A part is listed when a symbol resolves for it (#symbol_for): its own
# kicad_symbol, else its category's or the nearest ancestor's, else a guess
# from the category names (DEFAULT_SYMBOLS, KiCad's stock Device library).
# Obsolete parts are left out.
class KicadLibrary
  API_VERSION = "v1"
  TOKEN_PREFIX = "mskicad_"
  # "Library:Name", as KiCad writes symbol and footprint references.
  REFERENCE_FORMAT = /\A[^:\s][^:]*:[^:\s][^:]*\z/
  REFERENCE_MESSAGE = "must look like Library:Name"
  # How often a token's last use is written back (not on every call: KiCad
  # fetches a part each time one is placed).
  LAST_USED_RESOLUTION = 1.hour

  # Checked against each category name from the part's own category up to the
  # root; the first match wins.
  DEFAULT_SYMBOLS = [
    [ /potentiometer|trimmer/i, "Device:R_Potentiometer" ],
    [ /resistor/i, "Device:R" ],
    [ /electrolytic|polari[sz]ed|tantalum/i, "Device:C_Polarized" ],
    [ /capacitor/i, "Device:C" ],
    [ /ferrite/i, "Device:FerriteBead" ],
    [ /inductor|choke/i, "Device:L" ],
    [ /\bleds?\b/i, "Device:LED" ],
    [ /diode/i, "Device:D" ],
    [ /crystal|quartz|resonator/i, "Device:Crystal" ],
    [ /fuse/i, "Device:Fuse" ]
  ].freeze

  # --- Tokens ---------------------------------------------------------------

  def self.digest(token)
    ::Digest::SHA256.hexdigest(token.to_s)
  end

  # A new token for +organization+, replacing any previous one. Returns the
  # plain token: only its digest is stored.
  def self.issue_token!(organization)
    token = "#{TOKEN_PREFIX}#{SecureRandom.base58(40)}"
    organization.update_columns(kicad_token_digest: digest(token), kicad_token_created_at: Time.current, kicad_token_last_used_at: nil)
    token
  end

  def self.revoke_token!(organization)
    organization.update_columns(kicad_token_digest: nil, kicad_token_created_at: nil, kicad_token_last_used_at: nil)
  end

  # The organization the token was issued for, or nil.
  def self.authenticate(token)
    return nil unless token.to_s.start_with?(TOKEN_PREFIX)

    organization = Organization.find_by(kicad_token_digest: digest(token))
    return nil unless organization

    last_used = organization.kicad_token_last_used_at
    organization.update_column(:kicad_token_last_used_at, Time.current) if last_used.nil? || last_used < LAST_USED_RESOLUTION.ago
    organization
  end

  # The `.kicad_httplib` file KiCad loads (Preferences → Manage Symbol Libraries).
  def self.library_file(organization, token:, root_url:)
    JSON.pretty_generate(
      meta: { version: 1.0 },
      name: "MakerStorage - #{organization.name}",
      description: "Parts stocked in #{organization.name} (MakerStorage)",
      source: {
        type: "REST_API",
        api_version: API_VERSION,
        root_url: root_url,
        token: token,
        timeout_parts_seconds: 60,
        timeout_categories_seconds: 600
      }
    )
  end

  def self.library_filename(organization)
    "makerstorage-#{organization.name.parameterize.presence || 'organization'}.kicad_httplib"
  end

  # --- Library ----------------------------------------------------------------

  attr_reader :organization

  # +base_url+ (the request's) builds the links written into each part.
  def initialize(organization, base_url:)
    @organization = organization
    @base_url = base_url
  end

  # Categories holding at least one listed part, named by their full path
  # (KiCad's list is flat).
  def categories
    counts = listed_parts.group_by(&:category_id).transform_values(&:size)
    organization.categories.where(id: counts.keys).map do |category|
      {
        id: category.id.to_s,
        name: category.full_path(cache: category_cache),
        description: [ category.description.presence, "#{counts[category.id]} #{'part'.pluralize(counts[category.id])}" ].compact.join(" · ")
      }
    end.sort_by { |row| row[:name].downcase }
  end

  # The listed parts of one category (not its sub-categories, which KiCad
  # lists on their own), or nil when the organization has no such category.
  def category_parts(category_id)
    category = organization.categories.find_by(id: category_id)
    return nil unless category

    parts = listed_parts.select { |part| part.category_id == category.id }
    quantities = stock_by_part(parts.map(&:id))
    parts.map do |part|
      stock = "Stock: #{quantities.fetch(part.id, 0)}"
      { id: part.id.to_s, name: display_name(part), description: [ stock, part.description.presence ].compact.join(" · ") }
    end
  end

  # The part's symbol and fields, or nil when it isn't listed.
  def part(part_id)
    part = organization.parts.where.not(status: "obsolete")
      .includes(:tags, :storage_locations, :footprint, :datasheet_attachment, part_suppliers: :supplier)
      .find_by(id: part_id)
    symbol = part && symbol_for(part)
    return nil unless symbol

    preferred = part.part_suppliers.find(&:is_preferred) || part.part_suppliers.min_by(&:id)
    {
      id: part.id.to_s,
      name: display_name(part),
      symbolIdStr: symbol,
      exclude_from_bom: "False",
      exclude_from_board: "False",
      exclude_from_sim: "False",
      fields: compact_fields(
        "value" => [ part.value.presence || part.name, true ],
        "footprint" => footprint_for(part),
        "datasheet" => (stored_file_url(part.datasheet) if part.datasheet.attached?),
        "description" => part.description,
        "keywords" => part.tags.map(&:name).join(" "),
        "Manufacturer" => part.manufacturer,
        "MPN" => part.mpn,
        "IPN" => part.ipn,
        "Supplier" => preferred&.supplier&.name,
        "Supplier SKU" => preferred&.supplier_sku,
        "MakerStorage" => "#{@base_url}/parts/#{part.id}"
      )
    }
  end

  # The KiCad symbol for +part+ (see the class comment), or nil.
  def symbol_for(part)
    return part.kicad_symbol if part.kicad_symbol.present?

    chain = category_chain(part.category_id)
    chain.each { |category| return category.kicad_symbol if category.kicad_symbol.present? }
    chain.each do |category|
      DEFAULT_SYMBOLS.each { |pattern, symbol| return symbol if category.name.match?(pattern) }
    end
    nil
  end

  def footprint_for(part)
    part.kicad_footprint.presence || part.footprint&.kicad_footprint.presence
  end

  # Non-obsolete parts, split by whether KiCad gets them, for the settings page.
  def coverage
    candidates = organization.parts.where.not(status: "obsolete").select(:id, :category_id, :kicad_symbol).to_a
    listed = candidates.count { |part| symbol_for(part) }
    { listed: listed, without_symbol: candidates.size - listed }
  end

  private

  def listed_parts
    @listed_parts ||= organization.parts.where.not(status: "obsolete")
      .select(:id, :name, :ipn, :description, :category_id, :kicad_symbol)
      .order(:name, :id).to_a
      .select { |part| symbol_for(part) }
  end

  # The category and its ancestors, nearest first (guarded against a cycle).
  def category_chain(category_id)
    chain = []
    while (category = category_cache[category_id]) && chain.exclude?(category)
      chain << category
      category_id = category.parent_id
    end
    chain
  end

  def category_cache
    @category_cache ||= organization.categories.select(:id, :name, :parent_id, :kicad_symbol).index_by(&:id)
  end

  def stock_by_part(part_ids)
    PartStorage.where(part_id: part_ids).group(:part_id).sum(:quantity)
  end

  # KiCad keys its symbol cache by name across the whole library, so a name
  # two parts share gets the IPN (or id) appended. A colon would read as a
  # library separator.
  def display_name(part)
    name = part.name.tr(":", "-")
    duplicate_names.include?(part.name.downcase) ? "#{name} (#{part.ipn.presence || "##{part.id}"})" : name
  end

  def duplicate_names
    @duplicate_names ||= organization.parts.where.not(status: "obsolete")
      .group("LOWER(parts.name)").having("COUNT(*) > 1").pluck(Arel.sql("LOWER(parts.name)")).to_set
  end

  # name => value or [value, visible]; blank values are left out.
  def compact_fields(fields)
    fields.filter_map do |name, (value, visible)|
      [ name, { value: value.to_s, visible: visible ? "True" : "False" } ] if value.present?
    end.to_h
  end

  def stored_file_url(attachment)
    path = Rails.application.routes.url_helpers.stored_file_path(attachment.blob.signed_id, attachment.filename.to_s)
    "#{@base_url}#{path}"
  end
end

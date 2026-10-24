# frozen_string_literal: true

class McpServer
  # The tools that change the inventory, offered only to a grant with the
  # mcp:write scope whose user may write in the organization (see
  # OauthAuthorization#can_write?). They go through the same models as the
  # app, so every rule holds (no negative stock, one part per bag, unique
  # MPN/SKU…), and stock only ever changes through ledger movements signed
  # with the user and the client's name. Nothing here deletes anything.
  class WriteTools < Tools
    MAX_REASON_LENGTH = 500

    PART_FIELDS = {
      name: { type: "string", description: "Part name (2 to 255 characters)." },
      mpn: { type: "string", description: "Manufacturer part number (unique in the inventory)." },
      sku: { type: "string", description: "Internal SKU (unique in the inventory)." },
      barcode: { type: "string", description: "Barcode (unique in the inventory)." },
      manufacturer: { type: "string" },
      description: { type: "string" },
      value: { type: "string", description: "Component value, e.g. \"10k\", \"100nF\"." },
      package: { type: "string", description: "Package, e.g. \"0603\", \"SOIC-8\"." },
      tolerance: { type: "string", description: "e.g. \"1%\"." },
      voltage_rating: { type: "string", description: "e.g. \"50V\"." },
      power_rating: { type: "string", description: "e.g. \"0.1W\"." },
      category: { type: "string", description: "Existing category: full path (\"Passives > Resistors\") or unique name." },
      footprint: { type: "string", description: "Existing footprint name (see inventory_overview)." },
      unit: { type: "string", enum: Part::UNITS, description: "What the part is counted in (default piece). #{Part::DECIMAL_UNITS.join(', ')} take decimal quantities." },
      pack_size: { type: "number", exclusiveMinimum: 0, description: "How much one pack holds, in the part's unit (a 1 kg spool counted in gram: 1000)." },
      min_stock_threshold: { type: "number", minimum: 0, description: "Low-stock alert below this quantity." },
      target_stock: { type: "number", exclusiveMinimum: 0, description: "Quantity to reorder up to." },
      unit_price: { type: "number", minimum: 0, description: "Unit price in the organization's currency." },
      status: { type: "string", enum: Part::STATUSES },
      rohs_compliant: { type: "boolean" },
      storage_notes: { type: "string" }
    }.freeze
    # Free-text fields copied as given ("" clears an optional one).
    PART_TEXT_FIELDS = %w[name mpn sku barcode manufacturer description value tolerance voltage_rating power_rating storage_notes].freeze

    PART_LOOKUP = {
      part_id: { type: "integer", description: "Part id (from search_parts)." },
      part: { type: "string", description: "Or the part's IPN, MPN, SKU or barcode." }
    }.freeze
    REASON = { type: "string", maxLength: MAX_REASON_LENGTH, description: "Why, recorded in the stock ledger (e.g. \"Used for the LED badge workshop\")." }.freeze

    DEFINITIONS = [
      {
        name: "record_stock_movement",
        title: "Add or remove stock",
        description: "Record stock coming in (received, found, returned) or going out (used, given away, broken) for one part " \
                     "at one storage location. Writes a movement to the stock ledger. Without a location, stock goes into the " \
                     "part's bag or usual location, and comes out of the only location holding it. Stock can't go below zero.",
        inputSchema: {
          type: "object",
          required: %w[direction quantity],
          properties: PART_LOOKUP.merge(
            direction: { type: "string", enum: %w[in out], description: "in adds stock, out removes it." },
            quantity: { type: "number", exclusiveMinimum: 0, maximum: Quantity::MAX, description: "In the part's unit: whole for pieces, decimals allowed for a measure (2.5 meter)." },
            location_id: { type: "integer", description: "Storage location id." },
            location: { type: "string", description: "Or the location's code or exact name." },
            reason: REASON
          )
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }
      },
      {
        name: "move_stock",
        title: "Move stock",
        description: "Move a part's stock from one storage location to another (all of it by default). Writes a matching out " \
                     "and in movement to the ledger, together or not at all.",
        inputSchema: {
          type: "object",
          properties: PART_LOOKUP.merge(
            from_location_id: { type: "integer" },
            from_location: { type: "string", description: "Code or exact name of the location to take from. Optional when the part sits in one place." },
            to_location_id: { type: "integer" },
            to_location: { type: "string", description: "Code or exact name of the destination." },
            quantity: { type: "number", exclusiveMinimum: 0, maximum: Quantity::MAX, description: "Default: everything at the source." },
            reason: REASON
          )
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }
      },
      {
        name: "set_stock_count",
        title: "Record a stock count",
        description: "Record how many of a part were actually counted at one storage location. Writes an adjustment for " \
                     "the difference with the recorded stock (nothing when it already matches).",
        inputSchema: {
          type: "object",
          required: %w[counted_quantity],
          properties: PART_LOOKUP.merge(
            location_id: { type: "integer" },
            location: { type: "string", description: "Code or exact name. Optional when the part sits in one place." },
            counted_quantity: { type: "number", minimum: 0, maximum: Quantity::MAX, description: "In the part's unit." },
            reason: REASON
          )
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
      },
      {
        name: "create_part",
        title: "Create a part",
        description: "Add a new part to the inventory, optionally with its opening stock at a storage location. The IPN is " \
                     "generated the way the organization numbers parts. Search first (search_parts) so you don't create a duplicate.",
        inputSchema: {
          type: "object",
          required: %w[name category],
          properties: PART_FIELDS.merge(
            initial_quantity: { type: "number", minimum: 0, maximum: Quantity::MAX, description: "Opening stock, in the part's unit." },
            location_id: { type: "integer", description: "Where the opening stock is." },
            location: { type: "string", description: "Or its code or exact name." }
          )
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }
      },
      {
        name: "update_part",
        title: "Edit a part",
        description: "Change some fields of an existing part (only the fields given; an empty string clears an optional text " \
                     "field). Stock is changed with record_stock_movement, move_stock or set_stock_count, not here.",
        inputSchema: {
          type: "object",
          properties: PART_LOOKUP.merge(PART_FIELDS)
        },
        annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false }
      },
      {
        name: "create_project",
        title: "Create a project from a BOM",
        description: "Create a draft project from a list of components; each line is matched to a part like an imported " \
                     "BOM (MPN, SKU, value + footprint, name). Returns the project's availability, as get_project does. " \
                     "The user reviews the matches and confirms it in MakerStorage.",
        inputSchema: {
          type: "object",
          required: %w[name lines],
          properties: {
            name: { type: "string", description: "Project name." },
            description: { type: "string", maxLength: 255 },
            revision: { type: "string", maxLength: 20, description: "e.g. \"v1.2\"." },
            lines: Tools::DEFINITIONS.find { |tool| tool[:name] == "check_bom" }.dig(:inputSchema, :properties, :lines)
          }
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }
      }
    ].map { |tool| tool.merge(annotations: tool[:annotations].merge(title: tool[:title])) }.freeze

    def self.definitions
      DEFINITIONS
    end

    def self.names
      @names ||= DEFINITIONS.map { |tool| tool[:name] }
    end

    attr_reader :user, :client_name

    def initialize(organization:, base_url:, user:, client_name:)
      super(organization: organization, base_url: base_url)
      @user = user
      @client_name = client_name
    end

    private

    # Tools

    def record_stock_movement(arguments)
      part = find_part(part_lookup(arguments))
      direction = string_argument(arguments, "direction")
      raise ToolError, "direction must be in or out" unless %w[in out].include?(direction)

      quantity = quantity_argument(arguments, "quantity", default: nil, positive: true)
      raise ToolError, "quantity is required" if quantity.nil?

      location = location_argument(arguments, "location") ||
        (direction == "in" ? incoming_location(part) : only_location(part, "location"))
      default_reason = direction == "in" ? "Stock added" : "Stock removed"
      movement = write_movement(part, location, direction, direction == "in" ? quantity : -quantity, reason(arguments, default_reason))

      stock_result(part, location).merge(movement: movement_summary(movement))
    end

    def move_stock(arguments)
      part = find_part(part_lookup(arguments))
      source = location_argument(arguments, "from_location") || only_location(part, "from_location")
      destination = location_argument(arguments, "to_location")
      raise ToolError, "Give the destination (to_location or to_location_id)" if destination.nil?
      raise ToolError, "The source and the destination are the same location" if source == destination

      available = quantity_at(part, source)
      quantity = quantity_argument(arguments, "quantity", default: available, positive: true)
      raise ToolError, "There is no stock of this part in #{source.name}" if quantity.zero?

      given = string_argument(arguments, "reason")
      movements = ActiveRecord::Base.transaction do
        [
          write_movement(part, source, "out", -quantity, reason_text(given || "Moved to #{destination.name}")),
          write_movement(part, destination, "in", quantity, reason_text(given || "Moved from #{source.name}"))
        ]
      end

      stock_result(part, destination).merge(
        moved: quantity,
        from: { path: location_path(source), quantity: quantity_at(part, source) },
        movements: movements.map { |movement| movement_summary(movement) }
      )
    end

    def set_stock_count(arguments)
      part = find_part(part_lookup(arguments))
      counted = quantity_argument(arguments, "counted_quantity", default: nil, positive: false)
      raise ToolError, "counted_quantity is required" if counted.nil?

      location = location_argument(arguments, "location") || only_location(part, "location", allow_empty: false)
      difference = counted - quantity_at(part, location)
      return stock_result(part, location).merge(unchanged: true) if difference.zero?

      movement = write_movement(part, location, "adjustment", difference, reason(arguments, "Counted #{counted}"))
      stock_result(part, location).merge(unchanged: false, movement: movement_summary(movement))
    end

    def create_part(arguments)
      raise ToolError, "name is required" if string_argument(arguments, "name").nil?
      raise ToolError, "category is required (inventory_overview lists them)" if string_argument(arguments, "category").nil?

      part = organization.parts.build
      assign_part_fields(part, arguments)
      quantity = quantity_argument(arguments, "initial_quantity", default: 0, positive: false)
      location = location_argument(arguments, "location")
      raise ToolError, "Give the location of the opening stock (location or location_id)" if quantity.positive? && location.nil?

      # Box & bag numbering: opening stock in a bag makes it the part's bag;
      # anywhere else, the part mustn't take a free bag it will never fill
      # (same rules as the add-part form).
      if quantity.positive?
        if location.bag? && organization.ipn_generation_mode == "box_bag"
          part.bag = location
        else
          part.skip_bag_claim = true
        end
      end

      ActiveRecord::Base.transaction do
        save_part!(part)
        write_movement(part, location, "in", quantity, reason_text("Initial stock")) if quantity.positive?
      end

      { created: true }.merge(get_part("id" => part.id))
    end

    def update_part(arguments)
      part = find_part(part_lookup(arguments))
      assign_part_fields(part, arguments)
      raise ToolError, "Give at least one field to change" unless part.changed?

      changes = part.changes.except("updated_at").transform_values { |before, after| { from: before, to: after } }
      save_part!(part)
      { updated: true, changes: changes }.merge(get_part("id" => part.id))
    end

    def create_project(arguments)
      name = string_argument(arguments, "name")
      raise ToolError, "name is required" if name.nil?

      lines = arguments["lines"]
      raise ToolError, "lines must be a non-empty array of components" unless lines.is_a?(Array) && lines.any?
      raise ToolError, "At most #{MAX_BOM_LINES} lines per project" if lines.size > MAX_BOM_LINES

      project = organization.projects.new(
        name: name, status: "draft",
        description: string_argument(arguments, "description"), revision: string_argument(arguments, "revision")
      )
      matcher = BomParser::Matcher.new(organization)
      lines.each_with_index do |raw, index|
        raise ToolError, "Line #{index + 1} must be an object" unless raw.is_a?(Hash)

        line = {
          mpn: clean(raw["mpn"]), sku: clean(raw["sku"]), value: clean(raw["value"]),
          footprint: clean(raw["footprint"]), designation: clean(raw["name"])
        }
        part, match_type = matcher.match(line)
        part, match_type = loose_value_package_match(line), "value_footprint" if part.nil?
        project.project_lines.build(
          part: part,
          match_type: part ? match_type : "none",
          raw_reference: line[:mpn] || line[:sku],
          designation: line[:designation],
          value: line[:value],
          footprint: line[:footprint],
          designators: clean(raw["designators"]),
          quantity: quantity_argument(raw, "quantity", default: 1, positive: true, label: "Line #{index + 1} quantity")
        )
      end

      begin
        project.save_with_generated_reference! { Project.next_reference(organization) }
      rescue ActiveRecord::RecordInvalid
        raise ToolError, project.errors.full_messages.to_sentence
      end
      { created: true }.merge(get_project("id" => project.id))
    end

    # Writing

    # One ledger movement, signed by the user; refused movements (overdraw, a
    # bag held by another part…) come back as a tool error the model can read.
    def write_movement(part, location, type, delta, reason)
      organization.stock_movements.create!(
        part: part, storage_location: location, user: user,
        movement_type: type, quantity_delta: delta, reason: reason
      )
    rescue ActiveRecord::RecordInvalid => e
      raise ToolError, e.record.errors.full_messages.to_sentence
    end

    def save_part!(part)
      part.save!
    rescue ActiveRecord::RecordInvalid => e
      raise ToolError, e.record.errors.full_messages.to_sentence
    end

    def assign_part_fields(part, arguments)
      PART_TEXT_FIELDS.each do |field|
        next unless arguments.key?(field)

        value = arguments[field]
        raise ToolError, "#{field} must be a string" unless value.nil? || value.is_a?(String) || value.is_a?(Numeric)

        part[field] = value.to_s.strip.presence
      end
      part.package_type = clean(arguments["package"]) if arguments.key?("package")
      if arguments.key?("min_stock_threshold")
        part.min_stock_threshold = quantity_argument(arguments, "min_stock_threshold", default: 0, positive: false)
      end
      if arguments.key?("target_stock")
        part.target_stock = quantity_argument(arguments, "target_stock", default: nil, positive: true)
      end
      part.pack_size = quantity_argument(arguments, "pack_size", default: nil, positive: true) if arguments.key?("pack_size")
      part.unit_price = decimal_argument(arguments, "unit_price") if arguments.key?("unit_price")
      if arguments.key?("unit")
        unit = string_argument(arguments, "unit")
        raise ToolError, "unit must be one of #{Part::UNITS.join(', ')}" unless Part::UNITS.include?(unit)

        part.unit = unit
      end
      if arguments.key?("status")
        status = string_argument(arguments, "status")
        raise ToolError, "status must be one of #{Part::STATUSES.join(', ')}" unless Part::STATUSES.include?(status)

        part.status = status
      end
      part.rohs_compliant = boolean_argument(arguments, "rohs_compliant") if arguments.key?("rohs_compliant")
      part.category = find_category(string_argument(arguments, "category")) if arguments.key?("category")
      part.footprint = find_footprint(string_argument(arguments, "footprint")) if arguments.key?("footprint")
    end

    # Lookups

    def part_lookup(arguments)
      { "id" => arguments["part_id"], "reference" => arguments["part"] }
    end

    # The location named by "<key>_id" or "<key>" (code or exact name), or nil
    # when neither is given.
    def location_argument(arguments, key)
      lookup = { "id" => arguments["#{key}_id"], "code" => arguments[key] }
      return nil if lookup["id"].blank? && string_argument(lookup, "code").nil?

      find_storage_location(lookup)
    end

    # The one location holding the part, when the caller didn't say which.
    def only_location(part, key, allow_empty: true)
      held = part.part_storages.select { |storage| storage.quantity.nonzero? }
      held = part.part_storages.to_a if held.empty? && !allow_empty
      return held.sole.storage_location if held.one?

      if held.empty?
        raise ToolError, "#{part.name} has no stock anywhere. Give #{key} (code or name)."
      end
      places = held.map { |storage| "#{location_cache[storage.storage_location_id]&.code || storage.storage_location.name} (#{storage.quantity})" }
      raise ToolError, "#{part.name} is stored in several places: #{places.join(', ')}. Give #{key}."
    end

    # Where incoming stock goes without an explicit location: the part's bag,
    # else the first zone it was stocked in.
    def incoming_location(part)
      part.bag || part.fallback_storage_location ||
        raise(ToolError, "#{part.name} has no storage location yet. Give location (code or name).")
    end

    def find_category(name)
      return nil if name.nil?

      categories = organization.categories.to_a
      cache = categories.index_by(&:id)
      by_path = categories.select { |category| category.full_path(cache: cache).casecmp?(name) }
      by_path = categories.select { |category| category.name.casecmp?(name) } if by_path.empty?
      return by_path.sole if by_path.one?

      if by_path.empty?
        raise ToolError, "No category \"#{name}\". Use an existing one (inventory_overview lists them)."
      end
      raise ToolError, "Several categories are named \"#{name}\": #{by_path.map { |category| category.full_path(cache: cache) }.join(', ')}. Give the full path."
    end

    def find_footprint(name)
      return nil if name.nil?

      organization.footprints.find_by(Footprint.arel_table[:name].lower.eq(name.downcase)) ||
        raise(ToolError, "No footprint \"#{name}\". Use an existing one (inventory_overview lists them).")
    end

    # Results

    def quantity_at(part, location)
      PartStorage.where(part: part, storage_location: location).pick(:quantity) || 0
    end

    def stock_result(part, location)
      part.part_storages.reset
      {
        part: part_brief(part),
        location: { id: location.id, path: location_path(location), code: location.code, quantity: quantity_at(part, location) },
        on_hand: part.total_quantity,
        url: "#{base_url}/parts/#{part.id}"
      }
    end

    def movement_summary(movement)
      {
        id: movement.id,
        type: movement.movement_type,
        quantity_delta: movement.quantity_delta,
        location: location_path(movement.storage_location),
        reason: movement.reason
      }
    end

    def location_path(location)
      location.full_path(cache: location_cache)
    end

    # Arguments

    def reason(arguments, default)
      reason_text(string_argument(arguments, "reason") || default)
    end

    # Ledger reasons say which assistant made the change, next to the user's name.
    def reason_text(text)
      "#{text.truncate(MAX_REASON_LENGTH)} (via #{client_name.presence || 'MCP'})"
    end

    # A quantity in the part's unit (see Quantity): the part's validations
    # reject a fraction of a part counted in pieces.
    def quantity_argument(arguments, key, default:, positive:, label: key)
      raw = arguments[key]
      return default if raw.nil? || raw == ""

      value = Quantity.parse(raw)
      if value.nil? || (positive ? value <= 0 : value.negative?) || value > Quantity::MAX
        raise ToolError, "#{label} must be a number #{positive ? 'above 0' : 'of 0 or more'}, at most #{Quantity::MAX}"
      end

      value
    end

    def decimal_argument(arguments, key)
      raw = arguments[key]
      return nil if raw.nil? || raw == ""

      value = BigDecimal(raw.to_s, exception: false)
      raise ToolError, "#{key} must be a number of 0 or more" if value.nil? || value.negative?

      value
    end
  end
end

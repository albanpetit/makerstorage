# frozen_string_literal: true

class McpServer
  # The inventory tools McpServer exposes. Every query goes through the
  # organization (never a bare model lookup), and nothing here writes.
  class Tools
    class ToolError < StandardError; end

    SEARCH_LIMIT = 20
    MAX_SEARCH_LIMIT = 50
    MAX_BOM_LINES = 500
    # Purchase prices listed by get_part, most recent first.
    MAX_PURCHASES = 10
    MAX_BUILDS = 10_000
    MAX_ZONE_PARTS = 200
    LOW_STOCK_LIMIT = 25
    SIMILAR_LIMIT = 5
    MAX_LOANS = 100

    READ_ONLY = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }.freeze

    DEFINITIONS = [
      {
        name: "inventory_overview",
        title: "Inventory overview",
        description: "Summary of the organization's inventory: counts, category tree, footprints in use, " \
                     "whether stock reservations are on, and the parts currently below their minimum stock. " \
                     "Call it first to learn the vocabulary (category and footprint names) used by this inventory.",
        inputSchema: { type: "object", properties: {} }
      },
      {
        name: "search_parts",
        title: "Search parts",
        description: "Find parts in the inventory with their specs, stock (on hand, available after project " \
                     "reservations, incoming on open orders) and storage locations. Combine a free-text query " \
                     "with value / package filters to look for a component or a compatible substitute " \
                     "(e.g. value \"10k\" and package \"0603\").",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Free text matched against name, IPN, MPN, SKU, barcode, manufacturer, value and description." },
            value: { type: "string", description: "Component value, compared after normalization (\"4k7\" = \"4.7k\", \"100nF\" = \"100n\")." },
            package: { type: "string", description: "Package or footprint, e.g. \"0603\", \"SOIC-8\", \"R_0805_2012Metric\"." },
            category: { type: "string", description: "Category name (subcategories included)." },
            in_stock_only: { type: "boolean", description: "Only parts with stock available (default false)." },
            limit: { type: "integer", minimum: 1, maximum: MAX_SEARCH_LIMIT, description: "Maximum results (default #{SEARCH_LIMIT})." }
          }
        }
      },
      {
        name: "get_part",
        title: "Get part details",
        description: "Everything about one part: specs and technical parameters, stock per storage location, suppliers and prices " \
                     "(with quantity price breaks), recent purchase prices, open purchase orders, project reservations, the projects using it, " \
                     "and its consumption (units used over the organization's period and the low-stock threshold that usage suggests).",
        inputSchema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "Part id (from search_parts)." },
            reference: { type: "string", description: "IPN, MPN, SKU or barcode (exact, case-insensitive)." }
          }
        }
      },
      {
        name: "check_bom",
        title: "Check a BOM against stock",
        description: "Check whether a list of components (a BOM, a shopping list, a circuit idea) can be built " \
                     "from the inventory. Each line is matched like an imported BOM (MPN, then SKU or supplier " \
                     "part number, then value + footprint, then name) and compared with available stock. " \
                     "Returns the status of every line, the parts that are short, and how many builds are possible. " \
                     "Unmatched lines with a value list same-value parts in other packages as possible substitutes.",
        inputSchema: {
          type: "object",
          required: [ "lines" ],
          properties: {
            lines: {
              type: "array",
              maxItems: MAX_BOM_LINES,
              items: {
                type: "object",
                properties: {
                  designators: { type: "string", description: "Reference designators, e.g. \"R1, R2\" (echoed back)." },
                  mpn: { type: "string", description: "Manufacturer part number." },
                  sku: { type: "string", description: "Internal SKU or a supplier part number (LCSC, Mouser, DigiKey…)." },
                  value: { type: "string", description: "Value, e.g. \"10k\", \"100nF\"." },
                  footprint: { type: "string", description: "Footprint or package, e.g. \"0603\", \"Package_SO:SOIC-8_3.9x4.9mm_P1.27mm\"." },
                  name: { type: "string", description: "Part name or description, matched exactly against part names." },
                  quantity: { type: "integer", minimum: 1, description: "Quantity per build (default 1)." }
                }
              }
            },
            builds: { type: "integer", minimum: 1, maximum: MAX_BUILDS, description: "Number of boards/units to build (default 1)." }
          }
        }
      },
      {
        name: "list_projects",
        title: "List projects",
        description: "The organization's projects (imported BOMs) with their status, reservation and whether they can be built now.",
        inputSchema: {
          type: "object",
          properties: {
            status: { type: "string", enum: Project::STATUSES, description: "Only projects with this status." }
          }
        }
      },
      {
        name: "get_project",
        title: "Get project availability",
        description: "A project's BOM line by line with matched parts, what is missing to build it (taking " \
                     "other projects' reservations into account), what open orders will bring, and how many " \
                     "builds the stock allows.",
        inputSchema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "Project id (from list_projects)." },
            reference: { type: "string", description: "Project reference (PRJ-…) or exact name." },
            builds: { type: "integer", minimum: 1, maximum: MAX_BUILDS, description: "Number of builds to check (default 1)." }
          }
        }
      },
      {
        name: "list_loans",
        title: "List loans",
        description: "Tools and parts lent to members (or others): who has what, since when, the due date and " \
                     "whether it is overdue. Open loans by default (overdue ones included).",
        inputSchema: {
          type: "object",
          properties: {
            status: { type: "string", enum: Loan::STATUSES, description: "open (default, overdue included), overdue, or returned." },
            borrower: { type: "string", description: "Only loans whose borrower name contains this text." },
            limit: { type: "integer", minimum: 1, maximum: MAX_LOANS, description: "Maximum results (default #{MAX_LOANS})." }
          }
        }
      },
      {
        name: "get_storage_location",
        title: "Get storage location",
        description: "A storage zone (room, cabinet, drawer, box, bag…) with its sub-zones and the parts stored in it or below it.",
        inputSchema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "Storage location id." },
            code: { type: "string", description: "Zone code or exact name (case-insensitive)." }
          }
        }
      }
    ].map { |tool| tool.merge(annotations: READ_ONLY.merge(title: tool[:title])) }.freeze

    def self.definitions
      DEFINITIONS
    end

    def self.names
      @names ||= DEFINITIONS.map { |tool| tool[:name] }
    end

    attr_reader :organization, :base_url

    def initialize(organization:, base_url:)
      @organization = organization
      @base_url = base_url
    end

    def call(name, arguments)
      raise ToolError, "Unknown tool: #{name}" unless self.class.names.include?(name)

      send(name, arguments)
    end

    private

    # Tools

    def inventory_overview(_arguments)
      categories = organization.categories.to_a
      category_cache = categories.index_by(&:id)
      parts = organization.parts
      low_stock = parts.low_stock.alphabetical.limit(LOW_STOCK_LIMIT)
        .select("parts.*, COALESCE(SUM(part_storages.quantity), 0) AS on_hand_total").to_a

      {
        organization: organization.name,
        currency: organization.currency,
        stock_reservations_enabled: organization.stock_reservations_enabled,
        counts: {
          parts: parts.count,
          active_parts: parts.active.count,
          storage_locations: organization.storage_locations.count,
          projects: organization.projects.count,
          open_orders: organization.orders.where(status: Order::OPEN_STATUSES).count
        },
        categories: categories.map { |category| category.full_path(cache: category_cache) }.sort,
        footprints: organization.footprints.order(:name).pluck(:name),
        low_stock_parts_count: organization.low_stock_parts_count,
        low_stock_parts: low_stock.map do |part|
          { id: part.id, ipn: part.ipn, name: part.name, on_hand: Quantity.normalize(part.on_hand_total || 0), min_stock_threshold: part.min_stock_threshold }
        end
      }
    end

    def search_parts(arguments)
      limit = integer_argument(arguments, "limit", default: SEARCH_LIMIT, min: 1, max: MAX_SEARCH_LIMIT)
      scope = organization.parts

      if (query = string_argument(arguments, "query"))
        pattern = "%#{Part.sanitize_sql_like(query)}%"
        scope = scope.where(id: organization.parts.search(query).select(:id))
          .or(scope.where("parts.ipn LIKE ? ESCAPE '\\'", pattern))
      end
      if (category = string_argument(arguments, "category"))
        scope = scope.where(category_id: category_ids_matching(category))
      end

      value = BomParser::Matcher.normalize_value(string_argument(arguments, "value"))
      packages = BomParser::Matcher.package_candidates(string_argument(arguments, "package"))
      scope = scope.where.not(value: [ nil, "" ]) if value

      parts = scope.includes(:category, :footprint, :part_storages).alphabetical.to_a
      parts.select! { |part| BomParser::Matcher.normalize_value(part.value) == value } if value
      parts.select! { |part| part_packages(part).intersect?(packages) } if packages.any?

      stock = stock_figures(parts)
      parts.select! { |part| stock[part.id][:available].positive? } if boolean_argument(arguments, "in_stock_only")

      {
        total_matches: parts.size,
        truncated: parts.size > limit,
        parts: parts.first(limit).map { |part| part_summary(part, stock[part.id]) }
      }
    end

    def consumption_for(part, stock)
      consumption = PartConsumption.new(organization)
      entry = consumption.for_part(part)
      {
        period_days: consumption.window_days,
        used: entry&.consumed || 0,
        per_month: entry ? entry.monthly_rate.round(1) : 0,
        days_of_stock_left: entry&.days_left(stock[:on_hand]),
        suggested_min_stock_threshold: entry&.suggested_threshold
      }
    end

    def get_part(arguments)
      part = find_part(arguments)
      stock = stock_figures([ part ])[part.id]
      reservations = reserving_lines.where(part_id: part.id).group(:project_id).sum(:quantity)
      reserving_projects = organization.projects.where(id: reservations.keys).index_by(&:id)

      part_summary(part, stock).merge(
        description: part.description,
        consumption: consumption_for(part, stock),
        storage_notes: part.storage_notes,
        unit_price: part.unit_price&.to_f,
        target_stock: part.target_stock,
        lead_time_days: part.lead_time_days,
        has_datasheet: part.datasheet.attached?,
        files: part.attachments.map { |file| { filename: file.filename.to_s, content_type: file.content_type, byte_size: file.byte_size } },
        tags: part.tags.order(:name).pluck(:name),
        parameters: part.part_parameters.includes(:parameter_definition).sort_by { |parameter| parameter.name.downcase }
          .to_h { |parameter| [ parameter.name, parameter.display_value ] },
        suppliers: part.part_suppliers.includes(:supplier).sort_by { |link| [ link.is_preferred ? 0 : 1, link.supplier.name ] }.map do |link|
          {
            supplier: link.supplier.name,
            supplier_sku: link.supplier_sku,
            unit_price: link.unit_price&.to_f,
            price_breaks: link.price_breaks_for_json,
            lead_time_days: link.lead_time_days,
            preferred: link.is_preferred,
            url: link.url
          }
        end,
        recent_purchases: part.purchase_price_lines(:desc).limit(MAX_PURCHASES).map do |line|
          {
            date: (line.order.ordered_at || line.order.created_at.to_date).iso8601,
            reference: line.order.reference,
            supplier: line.order.supplier.name,
            status: line.order.status,
            quantity: line.quantity,
            unit_price: line.unit_price.to_f
          }
        end,
        open_orders: part.order_lines.joins(:order).merge(organization.orders.where(status: Order::OPEN_STATUSES))
          .includes(order: :supplier).map do |line|
            {
              reference: line.order.reference,
              supplier: line.order.supplier.name,
              status: line.order.status,
              quantity: line.quantity,
              expected_delivery: line.order.expected_delivery&.iso8601
            }
          end,
        reserved_by: reservations.map do |project_id, quantity|
          project = reserving_projects[project_id]
          { project_id: project_id, project: project&.name, reference: project&.reference, quantity: quantity }
        end,
        used_in_projects: part.project_lines.includes(:project).map(&:project).uniq.map do |project|
          { id: project.id, reference: project.reference, name: project.name, status: project.status }
        end
      )
    end

    def check_bom(arguments)
      lines = arguments["lines"]
      raise ToolError, "lines must be a non-empty array of components" unless lines.is_a?(Array) && lines.any?
      raise ToolError, "At most #{MAX_BOM_LINES} lines per check" if lines.size > MAX_BOM_LINES

      builds = integer_argument(arguments, "builds", default: 1, min: 1, max: MAX_BUILDS)
      matcher = BomParser::Matcher.new(organization)

      matched = lines.each_with_index.map do |raw, index|
        raise ToolError, "Line #{index + 1} must be an object" unless raw.is_a?(Hash)

        line = {
          mpn: clean(raw["mpn"]), sku: clean(raw["sku"]), value: clean(raw["value"]),
          footprint: clean(raw["footprint"]), designation: clean(raw["name"])
        }
        quantity = integer_argument(raw, "quantity", default: 1, min: 1, max: ApplicationRecord::MAX_INTEGER, label: "Line #{index + 1} quantity")
        part, match_type = matcher.match(line)
        part, match_type = loose_value_package_match(line), "value_footprint" if part.nil?
        match_type = "none" if part.nil?
        { raw: raw, line: line, quantity: quantity, part: part, match_type: match_type }
      end

      parts = organization.parts.where(id: matched.filter_map { |entry| entry[:part]&.id })
        .includes(:category, :footprint, :part_storages).index_by(&:id)
      stock = stock_figures(parts.values)
      per_build = matched.select { |entry| entry[:part] }.group_by { |entry| entry[:part].id }
        .transform_values { |entries| entries.sum { |entry| entry[:quantity] } }
      shortfalls = per_build.to_h { |part_id, quantity| [ part_id, [ quantity * builds - stock[part_id][:available], 0 ].max ] }

      result_lines = matched.map do |entry|
        echo = entry[:raw].slice("designators", "mpn", "sku", "value", "footprint", "name")
        if entry[:part]
          part = parts[entry[:part].id]
          figures = stock[part.id]
          short = shortfalls[part.id]
          echo.merge(
            quantity_per_build: entry[:quantity],
            status: short.positive? ? "short" : "ok",
            match_type: entry[:match_type],
            part: part_brief(part),
            part_required_total: per_build[part.id] * builds,
            available: figures[:available],
            missing: short,
            incoming: figures[:incoming],
            locations: locations_for(part)
          )
        else
          echo.merge(
            quantity_per_build: entry[:quantity],
            status: "unmatched",
            similar_parts: similar_parts(entry[:line][:value])
          )
        end
      end

      unmatched = result_lines.count { |line| line[:status] == "unmatched" }
      {
        builds: builds,
        buildable: unmatched.zero? && shortfalls.values.all?(&:zero?),
        max_builds: unmatched.zero? ? max_builds(per_build, stock) : nil,
        summary: {
          lines: result_lines.size,
          ok: result_lines.count { |line| line[:status] == "ok" },
          short: result_lines.count { |line| line[:status] == "short" },
          unmatched: unmatched
        },
        lines: result_lines
      }
    end

    def list_projects(arguments)
      scope = organization.projects.includes(project_lines: { part: :part_storages }).order(:name)
      if (status = string_argument(arguments, "status"))
        raise ToolError, "status must be one of #{Project::STATUSES.join(', ')}" unless Project::STATUSES.include?(status)

        scope = scope.where(status: status)
      end

      {
        stock_reservations_enabled: organization.stock_reservations_enabled,
        projects: scope.map do |project|
          {
            id: project.id,
            reference: project.reference,
            name: project.name,
            revision: project.revision,
            status: project.status,
            reserving_stock: project.reserving?,
            lines: project.project_lines.size,
            unmatched_lines: project.unmatched_lines.size,
            short_parts: project.shortfall_by_part.size,
            buildable: project.buildable?,
            builds_count: project.builds_count,
            last_built_at: project.last_built_at&.iso8601,
            url: "#{base_url}/projects/#{project.id}"
          }
        end
      }
    end

    def list_loans(arguments)
      status = string_argument(arguments, "status") || "open"
      raise ToolError, "status must be one of #{Loan::STATUSES.join(', ')}" unless Loan::STATUSES.include?(status)

      today = organization.local_date
      limit = integer_argument(arguments, "limit", default: MAX_LOANS, min: 1, max: MAX_LOANS)
      scope = case status
      when "open" then organization.loans.active
      when "overdue" then organization.loans.overdue_on(today)
      else organization.loans.closed
      end
      if (borrower = string_argument(arguments, "borrower"))
        scope = scope.where("loans.borrower_name LIKE ? ESCAPE '\\'", "%#{Loan.sanitize_sql_like(borrower)}%")
      end

      {
        today: today.iso8601,
        loans: scope.recent.limit(limit).includes(loan_lines: { part: :footprint }).map do |loan|
          {
            id: loan.id,
            reference: loan.reference,
            borrower: loan.borrower_name,
            status: loan.status(today),
            lent_at: loan.created_at.iso8601,
            due_on: loan.due_on&.iso8601,
            days_overdue: loan.days_overdue(today),
            returned_at: loan.closed_at&.iso8601,
            items: loan.loan_lines.map do |line|
              { part: part_brief(line.part), quantity: line.quantity, returned: line.returned_quantity,
                written_off: line.lost_quantity, outstanding: line.outstanding_quantity }
            end,
            url: "#{base_url}/loans/#{loan.id}"
          }
        end
      }
    end

    def get_project(arguments)
      project = find_project(arguments)
      builds = integer_argument(arguments, "builds", default: 1, min: 1, max: MAX_BUILDS)
      lines = project.project_lines.includes(part: [ :footprint, :part_storages ]).order(:id).to_a
      required = lines.select(&:part).group_by(&:part_id).transform_values { |part_lines| part_lines.sum(&:quantity) }
      parts = lines.filter_map(&:part).uniq.index_by(&:id)
      available = parts.transform_values { |part| project.available_for(part) }
      incoming = Order.incoming_quantities(organization, parts.keys)
      missing = required.to_h { |part_id, quantity| [ part_id, [ quantity * builds - available[part_id], 0 ].max ] }
      unmatched = lines.count { |line| line.part.nil? }

      {
        id: project.id,
        reference: project.reference,
        name: project.name,
        revision: project.revision,
        description: project.description,
        status: project.status,
        reserving_stock: project.reserving?,
        builds_checked: builds,
        buildable: lines.any? && unmatched.zero? && missing.values.all?(&:zero?),
        max_builds: lines.any? && unmatched.zero? ? max_builds(required, available.transform_values { |quantity| { available: quantity } }) : nil,
        builds_count: project.builds_count,
        url: "#{base_url}/projects/#{project.id}",
        lines: lines.map do |line|
          base = {
            designators: line.designators,
            reference: line.raw_reference,
            designation: line.designation,
            value: line.value,
            footprint: line.footprint,
            quantity_per_build: line.quantity,
            match_type: line.match_type
          }
          next base.merge(status: "unmatched") if line.part.nil?

          base.merge(
            status: missing[line.part_id].positive? ? "short" : "ok",
            part: part_brief(line.part),
            part_required_total: required[line.part_id] * builds,
            available: available[line.part_id],
            missing: missing[line.part_id],
            incoming: incoming.fetch(line.part_id, 0)
          )
        end
      }
    end

    def get_storage_location(arguments)
      zone = find_storage_location(arguments)
      zones = organization.storage_locations.to_a
      cache = zones.index_by(&:id)
      children_of = zones.group_by(&:parent_id)
      subtree = [ zone.id ]
      subtree.each { |id| subtree.concat(children_of.fetch(id, []).map(&:id)) }

      storages = PartStorage.where(storage_location_id: subtree).where.not(quantity: 0)
        .includes(part: :footprint).order(:storage_location_id).to_a.sort_by { |storage| storage.part.name }

      {
        id: zone.id,
        name: zone.name,
        code: zone.code,
        type: zone.location_type,
        path: zone.full_path(cache: cache),
        sub_zones: children_of.fetch(zone.id, []).sort_by { |child| [ child.position || 0, child.name ] }.map do |child|
          { id: child.id, name: child.name, code: child.code, type: child.location_type }
        end,
        parts_count: storages.size,
        truncated: storages.size > MAX_ZONE_PARTS,
        parts: storages.first(MAX_ZONE_PARTS).map do |storage|
          part_brief(storage.part).merge(quantity: storage.quantity, location: cache[storage.storage_location_id].full_path(cache: cache))
        end
      }
    end

    # Lookups (always through the organization)

    def find_part(arguments)
      if (id = arguments["id"]).present?
        organization.parts.find_by(id: id) || raise(ToolError, "No part with id #{id}")
      elsif (reference = string_argument(arguments, "reference"))
        %i[ipn mpn sku barcode].each do |column|
          part = organization.parts.find_by(Part.arel_table[column].lower.eq(reference.downcase))
          return part if part
        end
        raise ToolError, "No part with IPN, MPN, SKU or barcode \"#{reference}\". Try search_parts."
      else
        raise ToolError, "Give the part's id or reference"
      end
    end

    def find_project(arguments)
      if (id = arguments["id"]).present?
        organization.projects.find_by(id: id) || raise(ToolError, "No project with id #{id}")
      elsif (reference = string_argument(arguments, "reference"))
        organization.projects.find_by(Project.arel_table[:reference].lower.eq(reference.downcase)) ||
          organization.projects.find_by(Project.arel_table[:name].lower.eq(reference.downcase)) ||
          raise(ToolError, "No project with reference or name \"#{reference}\". Try list_projects.")
      else
        raise ToolError, "Give the project's id or reference"
      end
    end

    def find_storage_location(arguments)
      if (id = arguments["id"]).present?
        organization.storage_locations.find_by(id: id) || raise(ToolError, "No storage location with id #{id}")
      elsif (code = string_argument(arguments, "code"))
        organization.storage_locations.find_by(StorageLocation.arel_table[:code].lower.eq(code.downcase)) ||
          organization.storage_locations.find_by(StorageLocation.arel_table[:name].lower.eq(code.downcase)) ||
          raise(ToolError, "No storage location with code or name \"#{code}\"")
      else
        raise ToolError, "Give the storage location's id or code"
      end
    end

    def category_ids_matching(name)
      categories = organization.categories.select(:id, :name, :parent_id).to_a
      children_of = categories.group_by(&:parent_id)
      ids = categories.select { |category| category.name.downcase.include?(name.downcase) }.map(&:id)
      ids.each { |id| ids.concat(children_of.fetch(id, []).map(&:id) - ids) }
      ids
    end

    # Stock

    # { part_id => { on_hand:, reserved:, available:, incoming: } } for +parts+
    # (preload part_storages), in three queries whatever the number of parts.
    def stock_figures(parts)
      ids = parts.map(&:id)
      reserved = Project.reserved_quantities(organization, part_ids: ids)
      incoming = Order.incoming_quantities(organization, ids)
      parts.to_h do |part|
        on_hand = part.total_quantity
        held = reserved.fetch(part.id, 0)
        [ part.id, { on_hand: on_hand, reserved: held, available: [ on_hand - held, 0 ].max, incoming: incoming.fetch(part.id, 0) } ]
      end
    end

    def reserving_lines
      return ProjectLine.none unless organization.stock_reservations_enabled

      ProjectLine.joins(:project).merge(organization.projects.reserving)
    end

    # How many complete builds the stock covers: the scarcest part decides.
    def max_builds(required_per_build, stock)
      return 0 if required_per_build.empty?

      required_per_build.map { |part_id, quantity| stock.fetch(part_id)[:available] / quantity }.min
    end

    # Serialization

    def part_brief(part)
      {
        id: part.id,
        ipn: part.ipn,
        name: part.name,
        mpn: part.mpn,
        value: part.value,
        footprint: part.footprint&.name,
        package_type: part.package_type
      }
    end

    def part_summary(part, figures)
      part_brief(part).merge(
        manufacturer: part.manufacturer,
        category: part.category&.full_path(cache: category_cache),
        tolerance: part.tolerance,
        voltage_rating: part.voltage_rating,
        power_rating: part.power_rating,
        rohs_compliant: part.rohs_compliant,
        status: part.status,
        unit: part.unit,
        stock: figures.merge(min_stock_threshold: part.min_stock_threshold, low_stock: figures[:on_hand] < part.min_stock_threshold),
        locations: locations_for(part),
        url: "#{base_url}/parts/#{part.id}"
      )
    end

    def locations_for(part)
      part.part_storages.select { |storage| storage.quantity.nonzero? }.map do |storage|
        zone = location_cache[storage.storage_location_id]
        { path: zone&.full_path(cache: location_cache), code: zone&.code, quantity: storage.quantity }
      end
    end

    def location_cache
      @location_cache ||= organization.storage_locations.select(:id, :name, :parent_id, :code).index_by(&:id)
    end

    def category_cache
      @category_cache ||= Category.full_path_cache(organization.categories)
    end

    def part_packages(part)
      (BomParser::Matcher.package_candidates(part.footprint&.name) +
        BomParser::Matcher.package_candidates(part.package_type)).uniq
    end

    # The importer's value + footprint rule compares the BOM's footprint with
    # the part's whole footprint name, which suits EDA exports. A person (or
    # Claude) writes "0603" for a part filed under "R_0603_1608Metric", so
    # compare package candidates on both sides as well.
    def loose_value_package_match(line)
      value = BomParser::Matcher.normalize_value(line[:value])
      packages = BomParser::Matcher.package_candidates(line[:footprint])
      return nil if value.nil? || packages.empty?

      valued_parts.find do |part|
        BomParser::Matcher.normalize_value(part.value) == value && part_packages(part).intersect?(packages)
      end
    end

    def valued_parts
      @valued_parts ||= organization.parts.where.not(value: [ nil, "" ]).includes(:footprint).alphabetical.to_a
    end

    # Same-value parts (any package) for a BOM line nothing matched.
    def similar_parts(value)
      normalized = BomParser::Matcher.normalize_value(value)
      return [] if normalized.nil?

      candidates = valued_parts.select { |part| BomParser::Matcher.normalize_value(part.value) == normalized }.first(SIMILAR_LIMIT)
      stock = stock_figures(candidates)
      candidates.map { |part| part_brief(part).merge(available: stock[part.id][:available]) }
    end

    # Arguments

    def string_argument(arguments, key)
      clean(arguments[key])
    end

    def clean(value)
      value.is_a?(String) || value.is_a?(Numeric) ? value.to_s.strip.presence : nil
    end

    def boolean_argument(arguments, key)
      ActiveModel::Type::Boolean.new.cast(arguments[key]) || false
    end

    def integer_argument(arguments, key, default:, min:, max:, label: key)
      raw = arguments[key]
      return default if raw.nil? || raw == ""

      value = Integer(raw, exception: false)
      value = raw.to_i if value.nil? && raw.is_a?(Float) && raw == raw.floor
      raise ToolError, "#{label} must be an integer between #{min} and #{max}" if value.nil? || value < min || value > max

      value
    end
  end
end

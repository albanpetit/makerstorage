# Full backup of one organization's data as a ZIP archive, and the restore of
# such an archive into a new organization: for self-hosted installs, and for
# moving between an install and the hosted instance.
#
# The archive holds:
#   data.json        every record, with the source ids, plus the attachment index
#   csv/<table>.csv  the same rows as spreadsheets, for reading (import ignores them)
#   files/...        the Active Storage files (logos, footprint images, part
#                    images and datasheets)
#
# Left out on purpose: members and users (accounts belong to an install, not to
# an organization), the encrypted supplier API keys and DigiKey tokens (secrets,
# encrypted with the install's own keys), and the author of each stock movement
# and project build.
#
# A restore always creates a new organization owned by the importing user, so
# it never merges into (or overwrites) existing data. Every reference in the
# file is remapped through the ids created for this restore; a reference to a
# record the file doesn't contain aborts the restore, so imported rows can only
# ever point at the new organization's own records.
module OrganizationBackup
  FORMAT = "makerstorage-organization-backup"
  VERSION = 1
  DATA_ENTRY = "data.json"

  MAX_ARCHIVE_SIZE = 1.gigabyte
  # data.json is parsed in memory during the request: a few tens of MB already
  # hold tens of thousands of parts with their movements.
  MAX_DATA_SIZE = 50.megabytes
  MAX_ENTRIES = 100_000

  class Error < StandardError; end

  # Organization settings carried by a backup (no secrets, no `personal` flag).
  ORGANIZATION_ATTRIBUTES = %w[
    name email phone website address_line1 address_line2 city postcode country
    currency timezone
    ipn_generation_mode ipn_charset ipn_prefix ipn_separator ipn_digits ipn_use_category_code ipn_next_sequence
    default_low_stock_threshold allow_negative_stock stock_reservations_enabled
    notify_low_stock notify_late_orders notification_frequency
    lcsc_enabled
  ].freeze

  Table = Data.define(:name, :model, :scope, :references, :excluded, :enums) do
    def columns
      model.column_names - %w[organization_id] - excluded
    end

    def self_references
      references.select { |_, target| target == name }.keys
    end

    def attachment_limits
      model.respond_to?(:attachment_limits) ? model.attachment_limits : {}
    end
  end

  def self.table(name, model, scope, references: {}, excluded: [], enums: {})
    Table.new(name: name, model: model, scope: scope, references: references, excluded: excluded, enums: enums)
  end

  # Dependency order: a table only references tables listed before it (or
  # itself, for the category and zone trees).
  TABLES = [
    table("categories", Category, ->(org) { org.categories }, references: { "parent_id" => "categories" }),
    table("footprints", Footprint, ->(org) { org.footprints }, enums: { "mounting_type" => Footprint::MOUNTING_TYPES }),
    table("tags", Tag, ->(org) { org.tags }),
    table("suppliers", Supplier, ->(org) { org.suppliers }, enums: { "catalog_provider" => Supplier::CATALOG_PROVIDERS }),
    table("storage_locations", StorageLocation, ->(org) { org.storage_locations },
          references: { "parent_id" => "storage_locations" }, enums: { "location_type" => StorageLocation::LOCATION_TYPES }),
    table("parts", Part, ->(org) { org.parts },
          references: { "category_id" => "categories", "footprint_id" => "footprints", "bag_id" => "storage_locations" },
          enums: { "status" => Part::STATUSES, "unit" => Part::UNITS }),
    table("part_tags", PartTag, ->(org) { PartTag.where(part_id: org.parts.select(:id)) },
          references: { "part_id" => "parts", "tag_id" => "tags" }),
    table("part_suppliers", PartSupplier, ->(org) { PartSupplier.where(part_id: org.parts.select(:id)) },
          references: { "part_id" => "parts", "supplier_id" => "suppliers" }),
    table("part_storages", PartStorage, ->(org) { PartStorage.where(part_id: org.parts.select(:id)) },
          references: { "part_id" => "parts", "storage_location_id" => "storage_locations" }),
    table("orders", Order, ->(org) { org.orders }, references: { "supplier_id" => "suppliers" }, enums: { "status" => Order::STATUSES }),
    table("order_lines", OrderLine, ->(org) { OrderLine.where(order_id: org.orders.select(:id)) },
          references: { "order_id" => "orders", "part_id" => "parts" }),
    table("order_line_allocations", OrderLineAllocation,
          ->(org) { OrderLineAllocation.where(order_line_id: OrderLine.where(order_id: org.orders.select(:id)).select(:id)) },
          references: { "order_line_id" => "order_lines", "storage_location_id" => "storage_locations" }),
    table("projects", Project, ->(org) { org.projects }, enums: { "status" => Project::STATUSES }),
    table("project_lines", ProjectLine, ->(org) { ProjectLine.where(project_id: org.projects.select(:id)) },
          references: { "project_id" => "projects", "part_id" => "parts" }, enums: { "match_type" => ProjectLine::MATCH_TYPES }),
    table("project_builds", ProjectBuild, ->(org) { ProjectBuild.where(project_id: org.projects.select(:id)) },
          references: { "project_id" => "projects" }, excluded: %w[user_id]),
    # Last: a movement can point at the project build that wrote it.
    table("stock_movements", StockMovement, ->(org) { org.stock_movements },
          references: { "part_id" => "parts", "storage_location_id" => "storage_locations", "project_build_id" => "project_builds" },
          excluded: %w[user_id], enums: { "movement_type" => StockMovement::MOVEMENT_TYPES })
  ].freeze

  TABLES_BY_NAME = TABLES.index_by(&:name).freeze

  # Pseudo-table name the organization's own attachments (its logo) use.
  ORGANIZATION_TABLE = "organization"

  def self.attachment_limits_for(table_name)
    table_name == ORGANIZATION_TABLE ? Organization.attachment_limits : TABLES_BY_NAME[table_name]&.attachment_limits || {}
  end

  def self.filename_for(organization, at: Time.current)
    "makerstorage-#{organization.name.parameterize.presence || 'organization'}-#{at.strftime('%Y%m%d-%H%M')}.zip"
  end
end

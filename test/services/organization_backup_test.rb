require "test_helper"

class OrganizationBackupTest < ActiveSupport::TestCase
  setup do
    @owner = create_user
    @org = create_organization(name: "Fablab Amiens", currency: "USD", ipn_prefix: "FA", ipn_next_sequence: 42,
                               allow_negative_stock: false, stock_reservations_enabled: false,
                               mouser_api_key: "secret-mouser-key",
                               notify_late_orders: false, notification_frequency: "weekly", notifications_sent_on: Date.current)
    @org.organization_memberships.create!(user: @owner, role: "owner")
    @org.logo.attach(io: file_fixture("logo.png").open, filename: "logo.png", content_type: "image/png")

    @root_category = create_category(organization: @org, name: "Passives", code: "PAS")
    @category = create_category(organization: @org, name: "Resistors", code: "RES", parent: @root_category)
    @footprint = create_footprint(organization: @org, name: "0603", mounting_type: "SMD")
    @tag = create_tag(organization: @org, name: "Kit")
    @supplier = create_supplier(organization: @org, name: "Farnell")
    @mouser = @org.suppliers.find_by!(catalog_provider: "mouser")
    @mouser.update!(notes: "Account 1234")

    @room = create_storage_location(organization: @org, name: "Atelier", code: "AT")
    @drawer = create_storage_location(organization: @org, name: "Tiroir 1", code: "T1", location_type: "drawer", parent: @room)

    @part = create_part(organization: @org, category: @category, footprint: @footprint, name: "10k resistor",
                        mpn: "RC0603-10K", unit_price: "0.02", min_stock_threshold: 10)
    @part.tags << @tag
    @part.part_suppliers.create!(supplier: @supplier, supplier_sku: "F-10K", unit_price: "0.03", is_preferred: true)
    @part.part_suppliers.create!(supplier: @mouser, supplier_sku: "M-10K")
    @part.images.attach(io: file_fixture("logo.png").open, filename: "photo.png", content_type: "image/png")

    StockMovement.create!(organization: @org, part: @part, storage_location: @drawer, movement_type: "in",
                          quantity_delta: 100, user: @owner, created_at: 2.days.ago)
    StockMovement.create!(organization: @org, part: @part, storage_location: @drawer, movement_type: "out",
                          quantity_delta: -30, user: @owner)

    @order = create_order(organization: @org, supplier: @supplier, reference: "PO-0007")
    line = @order.order_lines.create!(part: @part, quantity: 50, unit_price: "0.03")
    line.allocations.create!(storage_location: @drawer, quantity: 50)

    @project = create_project(organization: @org, name: "Badge", reference: "PRJ-1", status: "confirmed",
                              reserved_at: 1.hour.ago)
    @project.project_lines.create!(part: @part, raw_reference: "RC0603-10K", quantity: 4, match_type: "mpn")
    @project.project_lines.create!(raw_reference: "UNKNOWN", quantity: 1, match_type: "none")
    @project.kicad_files.attach(io: file_fixture("kicad/board/board.kicad_sch").open, filename: "board.kicad_sch",
                                content_type: Project::KICAD_FILE_TYPE)
    build = @project.project_builds.create!(user: @owner, quantity: 2, built_at: 1.day.ago, note: "Workshop")
    StockMovement.create!(organization: @org, part: @part, storage_location: @drawer, movement_type: "out",
                          quantity_delta: -8, user: @owner, project_build: build)

    @stocktake = @org.stocktakes.create!(storage_location: @room, reference: "ST-1", user: @owner, blind: true)
    @stocktake.snapshot_stock!
    @stocktake.count!(@stocktake.stocktake_lines.first, 60, user: @owner)
    @stocktake.complete!(user: @owner)

    # Another tenant's data must stay out of the archive.
    @other = create_organization(name: "Other Lab")
    create_part(organization: @other, name: "Foreign part", mpn: "FOREIGN-1")

    @importer = create_user
  end

  test "an export restores into a new organization owned by the importer" do
    result = restore(export_zip(@org))
    org = result.organization

    assert_not_equal @org.id, org.id
    assert_equal "Fablab Amiens", org.name
    assert_not org.personal?
    assert @importer.owner_of?(org)
    assert_equal 1, org.organization_memberships.count
    assert_equal "USD", org.currency
    assert_equal false, org.stock_reservations_enabled
    assert_equal @org.reload.ipn_next_sequence, org.ipn_next_sequence
    assert_nil org.mouser_api_key, "secrets are not part of a backup"
    assert org.notify_low_stock
    assert_not org.notify_late_orders
    assert_equal "weekly", org.notification_frequency
    assert_nil org.notifications_sent_on, "the digest bookkeeping starts afresh"

    resistors = org.categories.find_by!(name: "Resistors")
    assert_equal "Passives", resistors.parent.name
    assert_equal "Atelier", org.storage_locations.find_by!(code: "T1").parent.name

    part = org.parts.find_by!(mpn: "RC0603-10K")
    assert_equal @part.ipn, part.ipn
    assert_equal resistors, part.category
    assert_equal "0603", part.footprint.name
    assert_equal [ "Kit" ], part.tags.map(&:name)
    assert_equal @part.reload.unit_price, part.unit_price
    assert_equal "Farnell", part.preferred_supplier.name
    assert_equal [ 100, -30, -8, -2 ], org.stock_movements.order(:created_at, :id).pluck(:quantity_delta)
    assert_equal [ nil ], org.stock_movements.distinct.pluck(:user_id)
    assert_equal @org.stock_movements.order(:id).pluck(:created_at).map(&:to_i),
                 org.stock_movements.order(:id).pluck(:created_at).map(&:to_i)

    order = org.orders.find_by!(reference: "PO-0007")
    assert_equal "Farnell", order.supplier.name
    assert_equal [ [ "Tiroir 1", 50 ] ], order.order_lines.first.allocations.map { |a| [ a.storage_location.name, a.quantity ] }

    project = org.projects.find_by!(reference: "PRJ-1")
    assert_equal [ part.id, nil ], project.project_lines.order(:id).pluck(:part_id)
    assert_equal @project.reserved_at.to_i, project.reserved_at.to_i
    restored_build = project.project_builds.sole
    assert_equal [ 2, "Workshop", nil ], [ restored_build.quantity, restored_build.note, restored_build.user_id ]
    assert_equal [ -8 ], restored_build.stock_movements.pluck(:quantity_delta)

    stocktake = org.stocktakes.find_by!(reference: "ST-1")
    assert stocktake.completed?
    assert stocktake.blind
    assert_equal "Atelier", stocktake.storage_location.name
    assert_nil stocktake.user_id
    assert_nil stocktake.completed_by_id
    stocktake_line = stocktake.stocktake_lines.sole
    assert_equal [ part, "Tiroir 1", 62, 60, nil ],
                 [ stocktake_line.part, stocktake_line.storage_location.name, stocktake_line.expected_quantity, stocktake_line.counted_quantity, stocktake_line.counted_by_id ]
    assert_equal org.stock_movements.find_by!(movement_type: "adjustment"), stocktake_line.stock_movement
    assert_equal 60, part.total_quantity

    assert_equal 1, org.suppliers.where(catalog_provider: "mouser").count
    assert_equal "Account 1234", org.suppliers.find_by!(catalog_provider: "mouser").notes
    assert_equal "M-10K", part.part_suppliers.joins(:supplier).find_by!(suppliers: { catalog_provider: "mouser" }).supplier_sku

    assert org.logo.attached?
    assert_equal [ "photo.png" ], part.images.map { |image| image.filename.to_s }
    assert_equal file_fixture("logo.png").binread, part.images.first.download
    assert_equal [ "board.kicad_sch" ], project.kicad_files.map { |file| file.filename.to_s }
    assert_equal file_fixture("kicad/board/board.kicad_sch").binread, project.kicad_files.first.download
    assert_equal 3, result.files_count
    assert_empty result.skipped_files

    assert_not org.parts.exists?(mpn: "FOREIGN-1")
    assert_equal 1, @other.parts.count
  end

  test "box & bag numbering comes back with each part in its own bag" do
    @org.update!(ipn_generation_mode: "box_bag")
    box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    bag = box.add_bags!(1).first
    bagged = create_part(organization: @org, category: @category, name: "Bagged part")
    assert_equal bag, bagged.reload.bag

    org = restore(export_zip(@org)).organization

    assert_equal "box_bag", org.ipn_generation_mode
    restored = org.parts.find_by!(name: "Bagged part")
    assert_equal "A-1", restored.ipn
    assert_equal org.storage_locations.find_by!(code: "A-1"), restored.bag
    assert_equal 1, restored.bag.position
    assert_equal "Box A", restored.bag.parent.name
  end

  # A reference left out of TABLES would be copied with the source
  # organization's id, pointing a restored record at another tenant's data.
  test "every foreign key column of a backed-up table is remapped" do
    OrganizationBackup::TABLES.each do |table|
      unmapped = table.columns.select { |column| column.end_with?("_id") } - table.references.keys
      assert_empty unmapped, "#{table.name} has foreign keys missing from OrganizationBackup::TABLES"
    end
  end

  test "the archive leaves out other organizations, members and secrets" do
    KicadLibrary.issue_token!(@org)
    Zip::File.open_buffer(export_zip(@org)) do |zip|
      data = JSON.parse(zip.read("data.json"))

      assert_equal OrganizationBackup::FORMAT, data["format"]
      assert_equal [ "FOREIGN-1" ], [ "FOREIGN-1" ] - data["tables"]["parts"].map { |row| row["mpn"] }
      assert_not data["organization"].key?("mouser_api_key")
      assert_not data["organization"].key?("kicad_token_digest")
      assert_not data["tables"].key?("organization_memberships")
      assert data["tables"]["stock_movements"].none? { |row| row.key?("user_id") }
      assert data["tables"]["parts"].none? { |row| row.key?("organization_id") }
      assert_includes zip.read("csv/parts.csv"), "RC0603-10K"
      assert_equal 3, data["attachments"].size
      data["attachments"].each { |entry| assert zip.find_entry(entry["path"]), entry["path"] }
    end
  end

  test "the restored organization can take a new name" do
    assert_equal "Fablab restored", restore(export_zip(@org), name: "Fablab restored").organization.name
  end

  test "rejects a file that is not a zip archive" do
    error = assert_raises(OrganizationBackup::Error) { restore("not a zip") }
    assert_match "not a valid backup archive", error.message
  end

  test "rejects an archive from another format or a newer version" do
    assert_raises(OrganizationBackup::Error) { restore(archive({ "format" => "something-else" })) }

    error = assert_raises(OrganizationBackup::Error) { restore(archive({ "version" => OrganizationBackup::VERSION + 1 })) }
    assert_match "newer version", error.message
  end

  test "rejects a reference to a record the backup doesn't hold, and creates nothing" do
    data = backup_data
    data["tables"]["parts"].first["category_id"] = 999_999

    assert_no_difference -> { Organization.count } do
      error = assert_raises(OrganizationBackup::Error) { restore(archive(data)) }
      assert_match "isn't in the backup", error.message
    end
  end

  test "rejects a category tree that loops back on itself" do
    data = backup_data
    passives = data["tables"]["categories"].find { |row| row["name"] == "Passives" }
    resistors = data["tables"]["categories"].find { |row| row["name"] == "Resistors" }
    passives["parent_id"] = resistors["id"]

    assert_no_difference -> { Organization.count } do
      error = assert_raises(OrganizationBackup::Error) { restore(archive(data)) }
      assert_match "loops back", error.message
    end
  end

  test "rejects unknown enumerated values" do
    data = backup_data
    data["tables"]["parts"].first["status"] = "stolen"

    error = assert_raises(OrganizationBackup::Error) { restore(archive(data)) }
    assert_match "stolen", error.message
  end

  test "rejects invalid organization settings" do
    data = backup_data
    data["organization"]["currency"] = "XXX"

    assert_no_difference -> { Organization.count } do
      error = assert_raises(OrganizationBackup::Error) { restore(archive(data)) }
      assert_match "Currency", error.message
    end
  end

  test "rejects rows that break a database constraint" do
    data = backup_data
    data["tables"]["parts"] << data["tables"]["parts"].first.merge("id" => 123_456)

    assert_no_difference -> { Organization.count } do
      assert_raises(OrganizationBackup::Error) { restore(archive(data)) }
    end
  end

  test "skips files of a type or size the attachment doesn't allow" do
    data = backup_data
    image = data["attachments"].find { |entry| entry["name"] == "images" }
    image.merge!("path" => "files/evil.html", "filename" => "evil.html", "content_type" => "text/html")
    logo = data["attachments"].find { |entry| entry["name"] == "logo" }
    logo.merge!("path" => "files/huge.png")

    result = restore(archive(data, files: {
      "files/evil.html" => "<html><script>alert(1)</script></html>",
      "files/huge.png" => "x" * (2.megabytes + 1)
    }))

    assert_equal [ "evil.html", "logo.png" ], result.skipped_files.sort
    assert_equal 1, result.files_count # the project's KiCad file
    assert_not result.organization.logo.attached?
    assert_not result.organization.parts.first.images.attached?
  end

  test "parameters, category templates and part values come back" do
    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω", description: "Nominal")
    dielectric = @org.parameter_definitions.create!(name: "Dielectric", value_type: "text")
    @category.update!(parameter_template: [ resistance.id ])
    @part.update!(parameter_values: { resistance.id => "10k", dielectric.id => "n/a" })

    org = restore(export_zip(@org)).organization

    restored = org.parameter_definitions.find_by!(name: "Resistance")
    assert_equal [ "Ω", "number", "Nominal" ], [ restored.unit, restored.value_type, restored.description ]
    assert_equal [ restored.id ], org.categories.find_by!(name: "Resistors").parameter_template_ids
    part = org.parts.find_by!(mpn: "RC0603-10K")
    assert_equal({ "Resistance" => [ "10k", 10_000.0 ], "Dielectric" => [ "n/a", nil ] },
                 part.part_parameters.includes(:parameter_definition).to_h { |p| [ p.name, [ p.value, p.numeric_value ] ] })
    assert_equal [ org.id ], ParameterDefinition.where(id: part.part_parameters.select(:parameter_definition_id)).distinct.pluck(:organization_id)
  end

  private

  def export_zip(organization)
    OrganizationBackup::Exporter.new(organization).to_zip
  end

  def backup_data
    data = nil
    Zip::File.open_buffer(export_zip(@org)) { |zip| data = JSON.parse(zip.read("data.json")) }
    data
  end

  # A backup archive from +data+ (merged over a real export's data.json), with
  # the real export's files plus +files+.
  def archive(data, files: {})
    source = export_zip(@org)
    Zip::OutputStream.write_buffer do |out|
      Zip::File.open_buffer(source) do |zip|
        zip.each do |entry|
          out.put_next_entry(entry.name)
          out.write(entry.name == "data.json" ? JSON.generate(JSON.parse(zip.read(entry)).merge(data)) : zip.read(entry))
        end
      end
      files.each do |path, content|
        out.put_next_entry(path)
        out.write(content)
      end
    end.string
  end

  def restore(bytes, name: nil)
    file = Tempfile.new([ "backup", ".zip" ], binmode: true)
    file.write(bytes)
    file.close
    OrganizationBackup::Importer.new(file.path, user: @importer, name: name).import!
  ensure
    file&.unlink
  end
end

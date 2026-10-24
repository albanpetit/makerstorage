require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @location = create_storage_location(organization: @org)

    @resistor = create_part(organization: @org, category: @category, name: "Resistor 10k", mpn: "RC0805-10K")
    @cap = create_part(organization: @org, category: @category, name: "Cap 100nF", sku: "CAP100NF")
    stock(@resistor, 5)
    stock(@cap, 100)
  end

  test "redirects a signed-out visitor to login" do
    get projects_path
    assert_redirected_to new_user_session_path
  end

  test "create refuses a CSV over the size limit without reading it" do
    user = create_user
    sign_in user

    stub_singleton(BomParser, :each_row, ->(*) { raise "the file must not be parsed" }) do
      file = csv_upload("x" * (BomParser::MAX_FILE_SIZE + 1))
      assert_no_difference "Project.count" do
        post projects_path, params: { file: file }
      end
    end

    assert_match(/too large/i, flash[:alert])
  end

  test "create parses a CSV, matches parts by mpn/sku/name and persists draft lines" do
    csv = <<~CSV
      Designation,MPN,SKU,Quantity
      Resistor 10k,RC0805-10K,,10
      Cap 100nF,,CAP100NF,4
      Mystery IC,UNKNOWN-1,,2
    CSV

    sign_in @user
    assert_difference -> { Project.count } => 1, -> { ProjectLine.count } => 3 do
      post projects_path, params: { name: "Weather station", file: csv_upload(csv) }
    end

    project = Project.order(:created_at).last
    assert_redirected_to project_path(project)
    assert_equal "draft", project.status
    assert_match(/\APRJ-/, project.reference)

    by_designation = project.project_lines.index_by(&:designation)
    assert_equal @resistor, by_designation["Resistor 10k"].part
    assert_equal "mpn", by_designation["Resistor 10k"].match_type
    assert_equal @cap, by_designation["Cap 100nF"].part
    assert_equal "sku", by_designation["Cap 100nF"].match_type
    assert_nil by_designation["Mystery IC"].part
    assert_equal "none", by_designation["Mystery IC"].match_type
  end

  test "create imports a KiCad netlist XML, matching by value + footprint and supplier part number" do
    cap = create_part(organization: @org, category: @category, name: "MLCC 100nF", value: "100n", package_type: "0603")
    resistor = create_part(organization: @org, category: @category, name: "Resistor 4.7k")
    PartSupplier.create!(part: resistor, supplier: create_supplier(organization: @org), supplier_sku: "C23162")
    # Same value + footprint in another organization: never offered.
    create_part(organization: create_organization, value: "BME280", package_type: "Bosch_LGA-8_2.5x2.5mm_P0.65mm_ClockwisePinNumbering")

    sign_in @user
    assert_difference -> { ProjectLine.count } => 3 do
      post projects_path, params: { file: Rack::Test::UploadedFile.new(file_fixture("kicad/sensor_board.xml"), "application/xml") }
    end

    project = Project.order(:created_at).last
    assert_equal "sensor_board", project.name
    by_value = project.project_lines.index_by(&:value)

    caps = by_value["100nF"]
    assert_equal [ cap, "value_footprint", 2, "C1, C2" ], [ caps.part, caps.match_type, caps.quantity, caps.designators ]
    assert_equal "Capacitor_SMD:C_0603_1608Metric", caps.footprint
    assert_equal [ resistor, "supplier_sku" ], [ by_value["4k7"].part, by_value["4k7"].match_type ]
    assert_equal "C23162", by_value["4k7"].raw_reference
    assert_nil by_value["BME280"].part
    assert_equal "BME280", by_value["BME280"].raw_reference
  end

  test "create reports XML that isn't a KiCad BOM" do
    file = Tempfile.new([ "bom", ".xml" ])
    file.write("<?xml version=\"1.0\"?><bom/>")
    file.rewind

    sign_in @user
    assert_no_difference -> { Project.count } do
      post projects_path, params: { file: Rack::Test::UploadedFile.new(file.path, "application/xml") }
    end
    assert_match(/KiCad/, flash[:alert])
  end

  test "create without a file or a name re-prompts" do
    sign_in @user
    assert_no_difference -> { Project.count } do
      post projects_path, params: { name: "  " }
    end
    assert_redirected_to projects_path
    assert_match(/name/i, flash[:alert])
  end

  test "create with only a name starts an empty draft project" do
    sign_in @user
    assert_difference -> { Project.count } => 1, -> { ProjectLine.count } => 0 do
      post projects_path, params: { name: "Weather station", revision: "A" }
    end

    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_equal [ "Weather station", "A", "draft", @org.id ], [ project.name, project.revision, project.status, project.organization_id ]
    assert_match(/\APRJ-/, project.reference)
  end

  test "update renames the project and sets its revision and description" do
    project = build_project([ @cap, 1, "sku" ])

    sign_in @user
    patch project_path(project), params: { project: { name: "Badge", revision: "B", description: "For the open day" } }

    assert_redirected_to project_path(project)
    assert_equal [ "Badge", "B", "For the open day" ], project.reload.values_at(:name, :revision, :description)
  end

  test "update reports an invalid name" do
    project = build_project([ @cap, 1, "sku" ])

    sign_in @user
    patch project_path(project), params: { project: { name: "x" } }

    assert_match(/name/i, flash[:alert])
    assert_not_equal "x", project.reload.name
  end

  test "viewers cannot edit or duplicate a project" do
    project = build_project([ @cap, 1, "sku" ])
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    patch project_path(project), params: { project: { name: "Hacked" } }
    assert_no_difference -> { Project.count } do
      post duplicate_project_path(project)
    end
    assert_not_equal "Hacked", project.reload.name
  end

  test "duplicate copies the project and its lines as the next revision" do
    project = build_project([ @cap, 4, "sku" ], [ nil, 1, "none" ])
    project.update!(name: "Badge", revision: "A", status: "confirmed")

    sign_in @user
    assert_difference -> { Project.count } => 1, -> { ProjectLine.count } => 2 do
      post duplicate_project_path(project)
    end

    copy = Project.order(:id).last
    assert_redirected_to project_path(copy)
    assert_equal [ "Badge", "B", "draft" ], [ copy.name, copy.revision, copy.status ]
    assert_equal [ [ @cap.id, 4 ], [ nil, 1 ] ], copy.project_lines.order(:id).pluck(:part_id, :quantity)
    assert_equal "confirmed", project.reload.status
  end

  test "duplicate takes the revision typed on the page" do
    project = build_project([ @cap, 4, "sku" ])

    sign_in @user
    post duplicate_project_path(project), params: { revision: "v2" }

    assert_equal "v2", Project.order(:id).last.revision
  end

  test "duplicating another organization's project is not found" do
    other = create_project(organization: create_organization)
    sign_in @user
    assert_no_difference -> { Project.count } do
      post duplicate_project_path(other)
    end
    assert_response :not_found
  end

  test "project_line create adds an inventory part by hand" do
    project = create_project(organization: @org)

    sign_in @user
    assert_difference -> { project.project_lines.count } => 1 do
      post project_project_lines_path(project), params: { project_line: { part_id: @resistor.id, quantity: 3, designators: "R1-R3" } }
    end

    line = project.project_lines.sole
    assert_redirected_to project_path(project)
    assert_equal [ @resistor, "manual", 3, "R1-R3", "RC0805-10K", "Resistor 10k" ],
                 [ line.part, line.match_type, line.quantity, line.designators, line.raw_reference, line.designation ]
  end

  test "project_line create adds a component that isn't in the inventory" do
    project = create_project(organization: @org)

    sign_in @user
    post project_project_lines_path(project), params: { project_line: { part_id: "", designation: "ESP32-C3 module", quantity: 1 } }

    line = project.project_lines.sole
    assert_nil line.part
    assert_equal [ "none", "ESP32-C3 module" ], [ line.match_type, line.designation ]

    get project_path(project)
    assert_equal 1, inertia_props["project"]["unmatched_count"]
  end

  test "project_line create needs a part or a designation" do
    project = create_project(organization: @org)

    sign_in @user
    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(project), params: { project_line: { part_id: "", designation: " ", quantity: 1 } }
    end
    assert_match(/designation/i, flash[:alert])
  end

  test "project_line create ignores another organization's part" do
    project = create_project(organization: @org)
    foreign = create_part(organization: create_organization, name: "Foreign")

    sign_in @user
    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(project), params: { project_line: { part_id: foreign.id, quantity: 1 } }
    end
  end

  test "project_line create on another organization's project is not found" do
    other = create_project(organization: create_organization)

    sign_in @user
    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(other), params: { project_line: { designation: "X", quantity: 1 } }
    end
    assert_response :not_found
  end

  test "project_line create reports an invalid quantity" do
    project = create_project(organization: @org)

    sign_in @user
    assert_no_difference -> { ProjectLine.count } do
      post project_project_lines_path(project), params: { project_line: { designation: "X", quantity: 0 } }
    end
    assert_match(/quantity/i, flash[:alert])
  end

  test "show serializes availability and sends the part pick-list after rendering" do
    project = build_project(
      [ @resistor, 10, "mpn" ],
      [ @cap, 4, "sku" ]
    )

    sign_in @user
    get project_path(project)
    assert_response :success

    lines = inertia_props["project"]["lines"]
    resistor_line = lines.find { |l| l["part"] && l["part"]["id"] == @resistor.id }
    assert_equal 5, resistor_line["in_stock"]
    assert_equal 5, resistor_line["shortfall"]
    assert_equal false, resistor_line["available"]
    assert_equal false, inertia_props["project"]["buildable"]

    page = JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])
    assert_not page["props"].key?("parts")
    assert_includes page["deferredProps"].values.flatten, "parts"

    foreign = create_part(organization: create_organization, name: "Foreign part")
    get project_path(project), headers: { "X-Inertia" => "true", "X-Inertia-Version" => page["version"].to_s,
                                          "X-Inertia-Partial-Component" => "projects/show", "X-Inertia-Partial-Data" => "parts" }
    part_ids = JSON.parse(@response.body)["props"]["parts"].map { |p| p["id"] }
    assert_includes part_ids, @resistor.id
    assert_not_includes part_ids, foreign.id
  end

  test "does not expose another organization's project" do
    other = create_project(organization: create_organization)
    sign_in @user
    get project_path(other)
    assert_response :not_found
  end

  test "project_line update re-points the match and records it as manual" do
    project = build_project([ nil, 3, "none" ])
    line = project.project_lines.first

    sign_in @user
    patch project_project_line_path(project, line), params: { project_line: { part_id: @resistor.id } }

    assert_equal @resistor, line.reload.part
    assert_equal "manual", line.match_type
  end

  test "project_line update can clear a match" do
    project = build_project([ @resistor, 3, "mpn" ])
    line = project.project_lines.first

    sign_in @user
    patch project_project_line_path(project, line), params: { project_line: { part_id: "" } }

    assert_nil line.reload.part
    assert_equal "none", line.match_type
  end

  test "confirm flips the project to confirmed and stamps checked_at" do
    project = build_project([ @cap, 4, "sku" ])
    sign_in @user
    post confirm_project_path(project)

    project.reload
    assert_equal "confirmed", project.status
    assert_not_nil project.checked_at
  end

  test "confirm reserves the project's stock when reservations are on" do
    project = build_project([ @cap, 4, "sku" ])
    sign_in @user
    post confirm_project_path(project)

    assert project.reload.reserving?
    assert_match(/reserved/i, flash[:notice])
  end

  test "confirm reserves nothing when the organization turned reservations off" do
    @org.update!(stock_reservations_enabled: false)
    project = build_project([ @cap, 4, "sku" ])
    sign_in @user
    post confirm_project_path(project)

    assert_equal "confirmed", project.reload.status
    assert_nil project.reserved_at
  end

  test "reserve and release toggle a confirmed project's reservation" do
    project = build_project([ @cap, 4, "sku" ])
    project.update!(status: "confirmed")
    sign_in @user

    post reserve_project_path(project)
    assert_not_nil project.reload.reserved_at

    post release_project_path(project)
    assert_nil project.reload.reserved_at
  end

  test "reserve refuses a draft project or an organization without reservations" do
    project = build_project([ @cap, 4, "sku" ])
    sign_in @user

    post reserve_project_path(project)
    assert_nil project.reload.reserved_at
    assert_match(/confirmed/i, flash[:alert])

    project.update!(status: "confirmed")
    @org.update!(stock_reservations_enabled: false)
    post reserve_project_path(project)
    assert_nil project.reload.reserved_at
  end

  test "viewers cannot reserve or release stock" do
    project = build_project([ @cap, 4, "sku" ])
    project.update!(status: "confirmed", reserved_at: Time.current)
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post release_project_path(project)

    assert_not_nil project.reload.reserved_at
  end

  test "show prices 1, 10 and 100 copies, plus the quantity asked for" do
    @resistor.update!(unit_price: 0.1)
    PartSupplier.create!(part: @cap, supplier: create_supplier(organization: @org, name: "Farnell"), is_preferred: true, unit_price: 0.05)
    project = build_project([ @resistor, 2, "mpn" ], [ @cap, 4, "sku" ])
    project.project_lines.create!(designation: "Custom coil", quantity: 1, match_type: "none")

    sign_in @user
    get project_path(project)
    cost = inertia_props["cost"]
    assert_equal "EUR", cost["currency"]
    assert_equal [ 1, 10, 100 ], cost["estimates"].map { |estimate| estimate["quantity"] }

    ten = cost["estimates"].second
    assert_in_delta 2.5, ten["stock_value"] # 5 × 0.10 + 40 × 0.05
    assert_in_delta 1.5, ten["purchase_cost"] # 15 resistors × 0.10
    assert_in_delta 0.4, ten["per_unit"]
    assert_equal [ false, 0, 1 ], ten.values_at("complete", "unpriced_count", "unmatched_count")
    assert_equal [ "Custom coil", 10 ], ten["unmatched"].sole.values_at("label", "quantity")
    resistor = ten["rows"].find { |row| row["part"]["id"] == @resistor.id }
    assert_equal [ 20, 5, 15, true ], resistor.values_at("required", "from_stock", "to_buy", "priced")
    assert_equal "Farnell", ten["rows"].find { |row| row["part"]["id"] == @cap.id }["supplier"]

    get project_path(project, cost_quantity: 25)
    assert_equal [ 1, 10, 25, 100 ], inertia_props["cost"]["estimates"].map { |estimate| estimate["quantity"] }
  end

  test "cost exports one quantity part by part as CSV, viewers included" do
    @resistor.update!(unit_price: 0.1)
    project = build_project([ @resistor, 2, "mpn" ], [ @cap, 1, "sku" ])
    project.project_lines.create!(raw_reference: "=COIL", quantity: 1, match_type: "none")
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")

    sign_in viewer
    get cost_project_path(project, quantity: 3)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/-cost-x3\.csv/, response.headers["Content-Disposition"])

    rows = CSV.parse(response.body)
    assert_equal [ "Part", "Name", "Needed", "From stock", "Stock unit price", "To buy", "Buy unit price", "Supplier", "Cost", "Priced" ], rows.first
    resistor = rows.find { |row| row[1] == "Resistor 10k" }
    assert_equal [ "6", "5", "0.1", "1", "0.1", "0.6" ], resistor.values_at(2, 3, 4, 5, 6, 8)
    assert_equal "no", rows.find { |row| row[1] == "Cap 100nF" }[9]
    assert_equal [ "'=COIL", "3", "not in inventory" ], rows.find { |row| row[9] == "not in inventory" }.values_at(0, 2, 9)
    assert_equal [ "Total", "0.6", "no" ], rows[-2].values_at(0, 8, 9)
    assert_equal [ "Per unit", "0.2" ], rows[-1].values_at(0, 8)
  end

  test "another organization's project cost is not found" do
    foreign = create_project(organization: create_organization)
    sign_in @user

    get cost_project_path(foreign)
    assert_response :not_found
  end

  test "reserving another organization's project is not found" do
    other_org = create_organization
    foreign = create_project(organization: other_org, status: "confirmed")
    sign_in @user

    post reserve_project_path(foreign)
    assert_response :not_found
    assert_nil foreign.reload.reserved_at
  end

  test "show subtracts earlier reservations from what the project can use" do
    earlier = build_project([ @cap, 80, "sku" ]) # stock 100
    earlier.update!(status: "confirmed", reserved_at: 1.hour.ago)
    project = build_project([ @cap, 30, "sku" ])

    sign_in @user
    get project_path(project)

    props = inertia_props["project"]
    assert props["reservations_enabled"]
    assert_not props["reserved"]
    line = props["lines"].first
    assert_equal 100, line["in_stock"]
    assert_equal 80, line["reserved_elsewhere"]
    assert_equal 10, line["shortfall"]
    assert_not props["buildable"]
  end

  test "build releases the project's reservation" do
    project = build_project([ @cap, 30, "sku" ])
    project.update!(status: "confirmed", reserved_at: Time.current)

    sign_in @user
    post build_project_path(project), params: { builds_count: 0 }

    assert_equal 70, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_nil project.reload.reserved_at
  end

  test "create_purchase_orders raises POs for short lines grouped by preferred supplier" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @resistor, supplier: supplier, is_preferred: true, unit_price: 0.10)
    project = build_project([ @resistor, 12, "mpn" ]) # stock is 5 -> shortfall 7

    sign_in @user
    assert_difference -> { Order.count } => 1, -> { OrderLine.count } => 1 do
      post create_purchase_orders_project_path(project)
    end

    line = OrderLine.order(:created_at).last
    assert_equal @resistor, line.part
    assert_equal 7, line.quantity
  end

  test "create_purchase_orders uses the preferred supplier's price break for the shortfall" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @resistor, supplier: supplier, is_preferred: true, unit_price: 0.10,
                         price_breaks: [ { quantity: 5, unit_price: "0.07" } ])
    project = build_project([ @resistor, 12, "mpn" ]) # shortfall 7

    sign_in @user
    post create_purchase_orders_project_path(project)

    assert_equal 0.07, OrderLine.order(:created_at).last.unit_price.to_f
  end

  test "create_purchase_orders creates no order at all when one supplier's order fails" do
    [ @resistor, @cap ].each_with_index do |part, i|
      PartSupplier.create!(part: part, supplier: create_supplier(organization: @org, name: "Supplier #{i}"), is_preferred: true)
    end
    project = build_project([ @resistor, 50, "mpn" ], [ @cap, 500, "sku" ]) # both short

    calls = 0
    original = OrderLine.method(:create!)
    failing = lambda do |*args, **kwargs|
      calls += 1
      raise ActiveRecord::RecordInvalid, OrderLine.new.tap { |l| l.errors.add(:base, "boom") } if calls == 2
      original.call(*args, **kwargs)
    end

    sign_in @user
    stub_singleton(OrderLine, :create!, failing) do
      assert_no_difference -> { Order.count } do
        post create_purchase_orders_project_path(project)
      end
    end
    assert_match(/no purchase order was created/i, flash[:alert])
  end

  test "create_purchase_orders orders only what open orders don't already cover, so a second click adds nothing" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @resistor, supplier: supplier, is_preferred: true, unit_price: 0.10)
    project = build_project([ @resistor, 12, "mpn" ]) # stock 5 -> shortfall 7
    open_order = create_order(organization: @org, supplier: supplier, reference: "PO-OPEN")
    open_order.order_lines.create!(part: @resistor, quantity: 3)

    sign_in @user
    post create_purchase_orders_project_path(project)
    assert_equal 4, OrderLine.where.not(order: open_order).last.quantity, "7 short - 3 already on order"

    assert_no_difference -> { Order.count } do
      post create_purchase_orders_project_path(project)
    end
    assert_match(/already on open purchase orders/i, flash[:alert])
  end

  test "create_purchase_orders warns when no short line has a supplier" do
    project = build_project([ @resistor, 12, "mpn" ])
    sign_in @user
    assert_no_difference -> { Order.count } do
      post create_purchase_orders_project_path(project)
    end
    assert_match(/no preferred supplier/i, flash[:alert])
  end

  test "build deducts required stock via out movements when buildable" do
    project = build_project([ @cap, 30, "sku" ]) # stock 100

    sign_in @user
    assert_difference -> { StockMovement.outbound.count } => 1 do
      post build_project_path(project), params: { builds_count: 0 }
    end

    assert_equal 70, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_match(/deducted/i, flash[:notice])
  end

  test "build deducts a part listed on two lines once, for the summed quantity" do
    project = build_project([ @cap, 30, "sku" ], [ @cap, 20, "manual" ]) # stock 100

    sign_in @user
    post build_project_path(project), params: { builds_count: 0 }

    assert_equal 50, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_match(/1 reference\b/, flash[:notice])
  end

  test "build records who built how many kits, and links the movements to it" do
    project = build_project([ @cap, 30, "sku" ]) # stock 100

    sign_in @user
    assert_difference -> { ProjectBuild.count } => 1 do
      post build_project_path(project), params: { builds_count: 0, kits: 3, note: "Open day" }
    end

    build = project.project_builds.sole
    assert_equal [ 3, "Open day", @user ], [ build.quantity, build.note, build.user ]
    assert_equal [ -90 ], build.stock_movements.pluck(:quantity_delta)
    assert_equal 10, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_equal 3, project.reload.builds_count
    assert_match(/3 kits/, flash[:notice])

    get project_path(project)
    history = inertia_props["project"]["builds"]
    assert_equal 1, history.size
    assert_equal [ 3, 90, 1, "Open day", "Test User" ], history.first.values_at("quantity", "units", "references", "note", "user")
  end

  test "build refuses more kits than the stock covers" do
    project = build_project([ @cap, 30, "sku" ]) # stock 100

    sign_in @user
    assert_no_difference [ "StockMovement.count", "ProjectBuild.count" ] do
      post build_project_path(project), params: { builds_count: 0, kits: 4 }
    end
    assert_match(/enough stock to build 4 kits/i, flash[:alert])
    assert_equal 0, project.reload.builds_count
  end

  test "build refuses a kit count out of range" do
    project = build_project([ @cap, 1, "sku" ])

    sign_in @user
    [ 0, -2, ProjectsController::MAX_BUILD_KITS + 1 ].each do |kits|
      assert_no_difference -> { StockMovement.count } do
        post build_project_path(project), params: { builds_count: 0, kits: kits }
      end
    end
    assert_match(/between 1 and/i, flash[:alert])
  end

  test "build is blocked when a part's lines together exceed its stock" do
    project = build_project([ @resistor, 3, "mpn" ], [ @resistor, 3, "manual" ]) # stock 5, needs 6

    sign_in @user
    assert_no_difference -> { StockMovement.count } do
      post build_project_path(project), params: { builds_count: 0 }
    end
    assert_match(/isn't buildable/i, flash[:alert])
  end

  test "create_purchase_orders orders a part's summed shortfall on one line" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @resistor, supplier: supplier, is_preferred: true, unit_price: 0.10)
    project = build_project([ @resistor, 4, "mpn" ], [ @resistor, 4, "manual" ]) # stock 5, needs 8

    sign_in @user
    assert_difference -> { OrderLine.count } => 1 do
      post create_purchase_orders_project_path(project)
    end
    assert_equal 3, OrderLine.order(:created_at).last.quantity
  end

  test "show marks a part's lines unavailable when together they exceed its stock" do
    project = build_project([ @resistor, 3, "mpn" ], [ @resistor, 3, "manual" ]) # stock 5, needs 6

    sign_in @user
    get project_path(project)

    lines = inertia_props["project"]["lines"]
    assert lines.none? { |line| line["available"] }
    assert lines.all? { |line| line["shortfall"] == 1 }
    assert_not inertia_props["project"]["buildable"]
  end

  test "build is blocked when the project isn't buildable" do
    project = build_project([ @resistor, 999, "mpn" ]) # short
    sign_in @user
    assert_no_difference -> { StockMovement.count } do
      post build_project_path(project), params: { builds_count: 0 }
    end
    assert_match(/isn't buildable/i, flash[:alert])
  end

  test "viewers cannot create a project" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    csv = "Designation,Quantity\nResistor 10k,1\n"
    assert_no_difference -> { Project.count } do
      post projects_path, params: { file: csv_upload(csv) }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "build records the kit and refuses a replayed submission" do
    project = build_project([ @cap, 30, "sku" ]) # stock 100

    sign_in @user
    post build_project_path(project), params: { builds_count: 0 }
    assert_equal 1, project.reload.builds_count
    assert project.last_built_at

    assert_no_difference [ "StockMovement.count", "ProjectBuild.count" ] do
      post build_project_path(project), params: { builds_count: 0 }
    end
    assert_match(/already built/i, flash[:alert])
    assert_equal 70, PartStorage.find_by(part: @cap, storage_location: @location).quantity
  end

  test "build without the page's builds count deducts nothing" do
    project = build_project([ @cap, 30, "sku" ])

    sign_in @user
    assert_no_difference -> { StockMovement.count } do
      post build_project_path(project)
    end
    assert_equal 0, project.reload.builds_count
  end

  test "another kit can be built from a fresh page" do
    project = build_project([ @cap, 30, "sku" ]) # stock 100

    sign_in @user
    post build_project_path(project), params: { builds_count: 0 }
    post build_project_path(project), params: { builds_count: 1 }

    assert_equal 2, project.reload.builds_count
    assert_equal 40, PartStorage.find_by(part: @cap, storage_location: @location).quantity
  end

  test "a build that fails halfway leaves no movements and no build count" do
    project = build_project([ @cap, 30, "sku" ], [ @resistor, 5, "mpn" ]) # stock 100 / 5

    # The resistor's stock vanishes between the buildability check and its
    # deduction (a concurrent movement), after the capacitor was already taken.
    original = PartStorage.method(:find_by)
    vanished = ->(*args, **kwargs) { kwargs[:part] == @resistor ? PartStorage.new(quantity: 0) : original.call(*args, **kwargs) }

    sign_in @user
    stub_singleton(PartStorage, :find_by, vanished) do
      assert_no_difference -> { StockMovement.count } do
        post build_project_path(project), params: { builds_count: 0 }
      end
    end

    assert_match(/could not deduct/i, flash[:alert])
    assert_equal 0, project.reload.builds_count
    assert_equal 0, project.project_builds.count
    assert_equal 100, PartStorage.find_by(part: @cap, storage_location: @location).quantity
  end

  test "updating a line without line params is a bad request, not a crash" do
    project = build_project([ @cap, 3, "sku" ])
    line = project.project_lines.first

    sign_in @user
    patch project_project_line_path(project, line)

    assert_response :bad_request
  end

  private

  test "a short line lists linked alternatives with stock this project can use, and switches to one" do
    project = create_project(organization: @org, name: "Timer")
    line = ProjectLine.create!(project: project, part: @resistor, quantity: 8, match_type: "mpn")
    spare = create_part(organization: @org, category: @category, name: "Resistor 10k other maker", mpn: "ERJ-6GEYJ103V")
    empty = create_part(organization: @org, category: @category, name: "Resistor 10k none left")
    stock(spare, 20)
    PartAlternative.link!(@resistor, spare)
    PartAlternative.link!(empty, @resistor)
    # Another project reserved 10 of the spare before this one.
    other = create_project(organization: @org, name: "Earlier", status: "confirmed", reserved_at: 1.day.ago)
    ProjectLine.create!(project: other, part: spare, quantity: 10, match_type: "mpn")
    sign_in @user

    get project_path(project)

    entry = inertia_props["project"]["lines"].sole
    assert_equal [ { "id" => spare.id, "reference" => "ERJ-6GEYJ103V", "name" => spare.name, "available" => 10 } ], entry["alternatives"]

    patch project_project_line_path(project, line), params: { project_line: { part_id: spare.id } }
    assert_equal [ spare, "manual" ], [ line.reload.part, line.match_type ]

    get project_path(project)
    assert_empty inertia_props["project"]["lines"].sole["alternatives"], "lines that aren't short list none"
  end

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @location,
      movement_type: "in", quantity_delta: quantity)
  end

  # Builds a persisted project with the given [part, quantity, match_type] lines.
  def build_project(*lines)
    project = create_project(organization: @org, reference: Project.next_reference(@org))
    lines.each do |part, quantity, match_type|
      project.project_lines.create!(part: part, quantity: quantity, match_type: match_type)
    end
    project
  end

  def csv_upload(content)
    file = Tempfile.new([ "bom", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

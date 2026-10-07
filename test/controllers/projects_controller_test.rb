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

  test "create without a file re-prompts" do
    sign_in @user
    assert_no_difference -> { Project.count } do
      post projects_path, params: { name: "Nope" }
    end
    assert_redirected_to projects_path
    assert_match(/choose a csv/i, flash[:alert])
  end

  test "show serializes availability and a part pick-list" do
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

    part_ids = inertia_props["parts"].map { |p| p["id"] }
    assert_includes part_ids, @resistor.id
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
      post build_project_path(project)
    end

    assert_equal 70, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_match(/deducted/i, flash[:notice])
  end

  test "build deducts a part listed on two lines once, for the summed quantity" do
    project = build_project([ @cap, 30, "sku" ], [ @cap, 20, "manual" ]) # stock 100

    sign_in @user
    post build_project_path(project)

    assert_equal 50, PartStorage.find_by(part: @cap, storage_location: @location).quantity
    assert_match(/1 reference\b/, flash[:notice])
  end

  test "build is blocked when a part's lines together exceed its stock" do
    project = build_project([ @resistor, 3, "mpn" ], [ @resistor, 3, "manual" ]) # stock 5, needs 6

    sign_in @user
    assert_no_difference -> { StockMovement.count } do
      post build_project_path(project)
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
      post build_project_path(project)
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

  private

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

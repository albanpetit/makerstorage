require "test_helper"

class PartsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get parts_path
    assert_redirected_to new_user_session_path
  end

  test "renders parts with the fields the inventory table needs" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors", color: "#F4A52B")
    location = create_storage_location(organization: org, name: "Shelf A")
    supplier = create_supplier(organization: org, name: "Mouser")
    part = create_part(organization: org, category: category, package_type: "0603", unit_price: 0.05)
    PartStorage.create!(part: part, storage_location: location, quantity: 25)
    PartSupplier.create!(part: part, supplier: supplier, is_preferred: true, unit_price: 0.04)

    sign_in user
    get parts_path
    assert_response :success

    part_json = inertia_props["parts"].find { |p| p["id"] == part.id }
    assert_equal "0603", part_json["package_type"]
    assert_equal 25, part_json["total_quantity"]
    assert_equal [ "Shelf A" ], part_json["location_names"]
    assert_equal "Mouser", part_json["supplier_name"]
    assert_equal category.id, part_json["category"]["id"]
    assert_equal "#F4A52B", part_json["category"]["color"]
  end

  test "serializes decimal fields as JSON numbers, not strings" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    supplier = create_supplier(organization: org)
    part = create_part(organization: org, category: category, unit_price: 12.5)
    PartSupplier.create!(part: part, supplier: supplier, unit_price: 9.99)

    sign_in user
    get part_path(part)
    assert_response :success

    part_json = inertia_props["part"]
    assert_kind_of Numeric, part_json["unit_price"]
    assert_equal 12.5, part_json["unit_price"]
    assert_kind_of Numeric, part_json["part_suppliers"].first["unit_price"]
    assert_equal 9.99, part_json["part_suppliers"].first["unit_price"]
  end

  test "show provides storages with location paths, movements, and location options" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    room = create_storage_location(organization: org, name: "Workshop", location_type: "room")
    shelf = create_storage_location(organization: org, name: "Shelf B2", location_type: "shelf", parent: room)
    part = create_part(organization: org, category: category)
    PartStorage.create!(part: part, storage_location: shelf, quantity: 40)
    StockMovement.create!(
      organization: org, part: part, storage_location: shelf, user: user,
      movement_type: "out", quantity_delta: -5, reason: "Project X"
    )

    sign_in user
    get part_path(part)
    assert_response :success

    storage = inertia_props["storages"].first
    assert_equal [ "Workshop", "Shelf B2" ], storage["location_path"]
    assert_equal 35, storage["quantity"]

    movement = inertia_props["movements"].first
    assert_equal "out", movement["movement_type"]
    assert_equal(-5, movement["quantity_delta"])
    assert_equal "Project X", movement["reason"]
    assert_equal "Shelf B2", movement["location_name"]

    assert inertia_props["storage_locations"].any? { |l| l["name"].include?("Shelf B2") }
  end

  test "destroy deletes a part without movements" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)

    sign_in user
    assert_difference -> { Part.count } => -1 do
      delete part_path(part)
    end
    assert_redirected_to parts_path
  end

  test "destroy refuses a part with recorded movements and reports the error" do
    user = create_user
    org = user.organizations.first
    location = create_storage_location(organization: org)
    part = create_part(organization: org)
    StockMovement.create!(
      organization: org, part: part, storage_location: location, user: user,
      movement_type: "in", quantity_delta: 10
    )

    sign_in user
    assert_no_difference "Part.count" do
      delete part_path(part)
    end
    assert_redirected_to part_path(part)
    follow_redirect!
    assert flash[:alert].present?
  end

  test "index passes through the search query param as initial_query" do
    user = create_user
    sign_in user

    get parts_path(search: "resistor")
    assert_response :success
    assert_equal "resistor", inertia_props["initial_query"]
  end

  test "index provides categories and storage_locations for the add-part modal" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    location = create_storage_location(organization: org, name: "Shelf A")

    sign_in user
    get parts_path
    assert_response :success

    props = inertia_props
    assert_includes props["categories"].map { |c| c["id"] }, category.id
    assert_includes props["storage_locations"].map { |l| l["id"] }, location.id
  end

  test "index provides footprints, suppliers, and tags for the add-part modal" do
    user = create_user
    org = user.organizations.first
    footprint = create_footprint(organization: org, name: "0603")
    supplier = create_supplier(organization: org, name: "Mouser")
    tag = create_tag(organization: org, name: "smd")

    sign_in user
    get parts_path
    assert_response :success

    props = inertia_props
    assert_includes props["footprints"].map { |f| f["id"] }, footprint.id
    assert_includes props["suppliers"].map { |s| s["id"] }, supplier.id
    assert_includes props["tags"].map { |t| t["id"] }, tag.id
  end

  test "index opens the add-part modal when the new param is present" do
    user = create_user

    sign_in user
    get parts_path(new: 1)
    assert_response :success
    assert_equal true, inertia_props["open_add"]

    get parts_path
    assert_equal false, inertia_props["open_add"]
  end

  test "create builds a part from the quick-add modal" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")

    sign_in user
    assert_difference -> { Part.count } => 1 do
      post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id } }
    end

    assert_redirected_to parts_path
    part = Part.find_by(name: "Resistor 10k")
    assert_equal category, part.category
  end

  test "create attaches the tags named by tag_ids" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    tag_a = create_tag(organization: org, name: "RoHS")
    tag_b = create_tag(organization: org, name: "favorite")

    sign_in user
    post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id, tag_ids: [ tag_a.id, tag_b.id ] } }

    part = Part.find_by(name: "Resistor 10k")
    assert_equal [ tag_a, tag_b ].sort, part.tags.sort
  end

  test "update replaces the set of attached tags" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    old_tag = create_tag(organization: org, name: "old")
    new_tag = create_tag(organization: org, name: "new")
    part.tags << old_tag

    sign_in user
    patch part_path(part), params: { part: { name: part.name, category_id: part.category_id, tag_ids: [ new_tag.id ] } }

    assert_equal [ new_tag ], part.reload.tags
  end

  test "update clears tags when tag_ids is empty" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    part.tags << create_tag(organization: org)

    sign_in user
    patch part_path(part), params: { part: { name: part.name, category_id: part.category_id, tag_ids: [] } }

    assert_empty part.reload.tags
  end

  test "create rejects a tag from another organization" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    foreign_tag = create_tag(organization: create_organization, name: "foreign")

    sign_in user
    assert_no_difference -> { Part.count } do
      post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id, tag_ids: [ foreign_tag.id ] } }
    end
  end

  test "edit serializes the tag options and the part's current tag_ids" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    tag = create_tag(organization: org, name: "RoHS")
    part.tags << tag

    sign_in user
    get edit_part_path(part)
    assert_response :success

    assert_includes inertia_props["part"]["tag_ids"], tag.id
    assert_includes inertia_props["tags"].map { |t| t["name"] }, "RoHS"
  end

  test "create assigns initial stock via a stock movement when a location and quantity are given" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    location = create_storage_location(organization: org, name: "Shelf A")

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      post parts_path, params: {
        part: { name: "Resistor 10k", category_id: category.id },
        initial_location_id: location.id,
        initial_quantity: "25"
      }
    end

    part = Part.find_by(name: "Resistor 10k")
    assert_equal 25, part.total_quantity
    movement = StockMovement.last
    assert_equal "in", movement.movement_type
    assert_equal location, movement.storage_location
  end

  test "create does not assign stock when no location is given" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")

    sign_in user
    assert_no_difference "StockMovement.count" do
      post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id }, initial_quantity: "25" }
    end
  end

  test "create redirects back to the referring page on validation failure" do
    user = create_user

    sign_in user
    post parts_path, params: { part: { name: "", category_id: "" } }, headers: { "HTTP_REFERER" => parts_url }

    assert_redirected_to parts_path
  end

  test "import creates new parts and auto-creates missing categories" do
    user = create_user
    sign_in user

    csv = <<~CSV
      Name,Category,MPN,Value,Unit Price
      Resistor 10k,Resistors,RES-10K,10kOhm,0.05
    CSV

    assert_difference -> { Part.count } => 1, -> { Category.count } => 1 do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/1 created, 0 updated, 0 skipped/, flash[:notice])

    part = Part.find_by(mpn: "RES-10K")
    assert_equal "Resistor 10k", part.name
    assert_equal "Resistors", part.category.name
  end

  test "import updates an existing part matched by mpn" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    create_part(organization: org, category: category, name: "Old name", mpn: "RES-10K")

    csv = <<~CSV
      Name,Category,MPN,Value
      Resistor 10k,Resistors,RES-10K,10kOhm
    CSV

    sign_in user
    assert_no_difference "Part.count" do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    assert_match(/0 created, 1 updated, 0 skipped/, flash[:notice])
    assert_equal "Resistor 10k", Part.find_by(mpn: "RES-10K").name
  end

  test "import skips rows missing a name or category" do
    user = create_user
    sign_in user

    csv = <<~CSV
      Name,Category,MPN
      ,Resistors,RES-1
      Resistor 4.7k,,RES-2
    CSV

    assert_no_difference "Part.count" do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    assert_match(/0 created, 0 updated, 2 skipped/, flash[:notice])
  end

  test "import recognizes French BOM-style column synonyms" do
    user = create_user
    sign_in user

    csv = <<~CSV
      Reference;Designation;Categorie;Valeur;Boitier;Emplacement;Fournisseur;Quantite;Seuil;PU_EUR
      RES-10K;Resistor 10k;Resistors;10kOhm;0603;Shelf A;Mouser;150;50;0,05
    CSV

    assert_difference -> { Part.count } => 1, -> { StorageLocation.count } => 1 do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    part = Part.find_by(sku: "RES-10K")
    assert_equal "Resistor 10k", part.name
    assert_equal "0603", part.package_type
    assert_equal 50, part.min_stock_threshold
    assert_equal 150, part.total_quantity
    assert_equal [ "Shelf A" ], part.storage_locations.map(&:name)
    assert_equal 0.05, part.unit_price.to_f
  end

  test "import assigns quantity to the named location, creating it if needed" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    location = create_storage_location(organization: org, name: "Existing Shelf")
    part = create_part(organization: org, category: category, mpn: "RES-10K")
    PartStorage.create!(part: part, storage_location: location, quantity: 5)

    csv = <<~CSV
      Name,Category,MPN,Location,Quantity
      Resistor 10k,Resistors,RES-10K,Existing Shelf,40
    CSV

    sign_in user
    assert_no_difference "StorageLocation.count" do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    assert_equal 40, PartStorage.find_by(part: part, storage_location: location).quantity
  end

  test "import without a location column leaves stock untouched" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    create_part(organization: org, category: category, mpn: "RES-10K")

    csv = <<~CSV
      Name,Category,MPN
      Resistor 10k,Resistors,RES-10K
    CSV

    sign_in user
    assert_no_difference [ "StorageLocation.count", "PartStorage.count" ] do
      post import_parts_path, params: { file: csv_upload(csv) }
    end
  end

  test "import redirects with an alert when no file is given" do
    user = create_user
    sign_in user

    post import_parts_path
    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a CSV file/, flash[:alert])
  end

  test "index advertises supplier lookup only when a key is configured" do
    user = create_user
    sign_in user

    get parts_path
    assert_equal false, inertia_props["supplier_lookup_enabled"]

    user.organizations.first.update!(mouser_api_key: "abc123")
    get parts_path
    assert_equal true, inertia_props["supplier_lookup_enabled"]
  end

  test "lookup returns normalized catalog results as JSON" do
    user = create_user
    user.organizations.first.update!(mouser_api_key: "abc123")
    sign_in user

    result = SupplierCatalog::PartResult.new(mpn: "RC0805FR-0710KL", manufacturer: "YAGEO", provider: "mouser")
    stub_singleton(SupplierCatalog, :lookup, ->(*, **) { [ result ] }) do
      post lookup_parts_path, params: { mpn: "RC0805FR-0710KL" }
    end

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "RC0805FR-0710KL", body["results"].first["mpn"]
    assert_equal "YAGEO", body["results"].first["manufacturer"]
  end

  test "lookup rejects a blank part number" do
    user = create_user
    user.organizations.first.update!(mouser_api_key: "abc123")
    sign_in user

    post lookup_parts_path, params: { mpn: "  " }
    assert_response :unprocessable_entity
    assert_match(/Enter a part number/, JSON.parse(@response.body)["error"])
  end

  test "lookup reports when no catalog is configured" do
    user = create_user
    sign_in user

    post lookup_parts_path, params: { mpn: "RC0805" }
    assert_response :unprocessable_entity
    assert_match(/No supplier catalog is configured/, JSON.parse(@response.body)["error"])
  end

  test "lookup surfaces upstream failures as a bad gateway" do
    user = create_user
    user.organizations.first.update!(mouser_api_key: "abc123")
    sign_in user

    stub_singleton(SupplierCatalog, :lookup, ->(*, **) { raise SupplierCatalog::LookupError, "Mouser is down" }) do
      post lookup_parts_path, params: { mpn: "RC0805" }
    end
    assert_response :bad_gateway
    assert_match(/Mouser is down/, JSON.parse(@response.body)["error"])
  end

  test "create attaches a supplier-provided datasheet and image" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    sign_in user

    download = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("%PDF-1.4 fake"), filename: "ds.pdf", content_type: "application/pdf"
    )
    image = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("fake-image-bytes"), filename: "img.png", content_type: "image/png"
    )

    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(url, **) { url.end_with?(".pdf") ? download : image }) do
      post parts_path, params: {
        part: { name: "Resistor 10k", category_id: category.id },
        datasheet_url: "https://www.mouser.com/ds.pdf",
        image_url: "https://www.mouser.com/img.png"
      }
    end

    part = org.parts.find_by(name: "Resistor 10k")
    assert part.datasheet.attached?
    assert part.images.attached?
  end

  test "update attaches a supplier-provided datasheet and image" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    sign_in user

    download = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("%PDF-1.4 fake"), filename: "ds.pdf", content_type: "application/pdf"
    )
    image = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("fake-image-bytes"), filename: "img.png", content_type: "image/png"
    )

    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(url, **) { url.end_with?(".pdf") ? download : image }) do
      patch part_path(part), params: {
        part: { name: part.name, category_id: part.category_id },
        datasheet_url: "https://www.mouser.com/ds.pdf",
        image_url: "https://www.mouser.com/img.png"
      }
    end

    part.reload
    assert part.datasheet.attached?
    assert part.images.attached?
  end

  test "edit advertises supplier lookup based on configuration" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    sign_in user

    get edit_part_path(part)
    assert_equal false, inertia_props["supplier_lookup_enabled"]

    org.update!(mouser_api_key: "abc123")
    get edit_part_path(part)
    assert_equal true, inertia_props["supplier_lookup_enabled"]
  end

  test "create still succeeds when a remote asset download fails" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    sign_in user

    stub_singleton(SupplierCatalog::RemoteFile, :download, ->(*, **) { nil }) do
      post parts_path, params: {
        part: { name: "Resistor 20k", category_id: category.id },
        datasheet_url: "https://www.mouser.com/ds.pdf"
      }
    end

    part = org.parts.find_by(name: "Resistor 20k")
    assert part.present?
    refute part.datasheet.attached?
  end

  private

  def csv_upload(content)
    file = Tempfile.new([ "import", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

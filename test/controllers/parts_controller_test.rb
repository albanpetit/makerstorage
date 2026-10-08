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

  test "serializes a thumbnail_url for parts with an attached image" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    with_image = create_part(organization: org, category: category, name: "With image")
    without_image = create_part(organization: org, category: category, name: "No image")
    non_image = create_part(organization: org, category: category, name: "Non-image attachment")
    hotlinked = create_part(
      organization: org, category: category, name: "Hotlinked",
      image_source_url: "https://www.mouser.com/img.png"
    )
    with_image.images.attach(
      io: StringIO.new("fake-image-bytes"), filename: "part.png", content_type: "image/png"
    )
    # A non-image attachment (e.g. an HTML error page a supplier returned in
    # place of an image) must not surface as a thumbnail.
    non_image.images.attach(
      io: StringIO.new("<html>not an image</html>"), filename: "oops.html", content_type: "text/html"
    )

    sign_in user
    get parts_path
    assert_response :success

    with_json = inertia_props["parts"].find { |p| p["id"] == with_image.id }
    without_json = inertia_props["parts"].find { |p| p["id"] == without_image.id }
    non_image_json = inertia_props["parts"].find { |p| p["id"] == non_image.id }
    hotlinked_json = inertia_props["parts"].find { |p| p["id"] == hotlinked.id }
    assert with_json["thumbnail_url"].present?, "expected a thumbnail URL for a part with an image"
    assert_nil without_json["thumbnail_url"]
    assert_nil non_image_json["thumbnail_url"]
    # No uploaded image: fall back to the hotlinked supplier URL.
    assert_equal "https://www.mouser.com/img.png", hotlinked_json["thumbnail_url"]

    # The URL must serve the image without an image processor (no variant): the
    # member-only file route serves the original bytes.
    get with_json["thumbnail_url"]
    assert_response :success
    assert_equal "fake-image-bytes", response.body
  end

  test "serializes decimal fields as JSON numbers, not strings" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    supplier = create_supplier(organization: org)
    part = create_part(organization: org, category: category, unit_price: 12.5)
    PartSupplier.create!(part: part, supplier: supplier, unit_price: 9.99)

    sign_in user
    get part_path(part), headers: { "Accept" => "application/json" }
    assert_response :success

    part_json = JSON.parse(response.body)["part"]
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
    get part_path(part), headers: { "Accept" => "application/json" }
    assert_response :success
    props = JSON.parse(response.body)

    storage = props["storages"].first
    assert_equal [ "Workshop", "Shelf B2" ], storage["location_path"]
    assert_equal 35, storage["quantity"]

    movement = props["movements"].first
    assert_equal "out", movement["movement_type"]
    assert_equal(-5, movement["quantity_delta"])
    assert_equal "Project X", movement["reason"]
    assert_equal "Shelf B2", movement["location_name"]

    assert props["storage_locations"].any? { |l| l["name"].include?("Shelf B2") }
  end

  test "show redirects a direct HTML visit to the inventory list" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, category: create_category(organization: org))

    sign_in user
    get part_path(part)
    assert_redirected_to parts_path
  end

  test "show responds with the part detail as JSON for the detail sidebar" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    shelf = create_storage_location(organization: org, name: "Shelf B2", location_type: "shelf")
    part = create_part(organization: org, category: category)
    PartStorage.create!(part: part, storage_location: shelf, quantity: 40)

    sign_in user
    get part_path(part), headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "application/json", response.media_type

    body = JSON.parse(response.body)
    assert_equal part.id, body["part"]["id"]
    assert_equal 40, body["storages"].first["quantity"]
    assert body.key?("movements")
    assert body.key?("storage_locations")
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
    assert_redirected_to parts_path
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

  test "create persists a manually entered ipn in manual mode" do
    user = create_user
    org = user.organizations.first
    org.update!(ipn_generation_mode: "manual")
    category = create_category(organization: org, name: "Resistors")

    sign_in user
    post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id, ipn: "MS-0042" } }

    assert_equal "MS-0042", Part.find_by(name: "Resistor 10k").ipn
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

  test "edit responds with the full part as JSON for the edit modal" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    supplier = create_supplier(organization: org, name: "Mouser")
    part = create_part(organization: org, category: category, mpn: "RES-10K", description: "10k resistor")
    PartSupplier.create!(part: part, supplier: supplier, supplier_sku: "M-1", unit_price: 0.04)

    sign_in user
    get edit_part_path(part), headers: { "Accept" => "application/json" }
    assert_response :success

    body = JSON.parse(response.body)["part"]
    assert_equal part.id, body["id"]
    assert_equal "RES-10K", body["mpn"]
    assert_equal "10k resistor", body["description"]
    assert_equal category.id, body["category_id"]
    assert_equal "M-1", body["part_suppliers"].first["supplier_sku"]
  end

  test "edit denies JSON access to a part from another organization" do
    user = create_user
    foreign_part = create_part(organization: create_organization)

    sign_in user
    get edit_part_path(foreign_part), headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "update links a new supplier via nested attributes" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    supplier = create_supplier(organization: org, name: "Mouser")

    sign_in user
    assert_difference -> { part.part_suppliers.count }, 1 do
      patch part_path(part), params: { part: {
        name: part.name, category_id: part.category_id,
        part_suppliers_attributes: [ { supplier_id: supplier.id, supplier_sku: "M-1", is_preferred: true } ]
      } }
    end

    link = part.part_suppliers.reload.first
    assert_equal supplier.id, link.supplier_id
    assert_equal "M-1", link.supplier_sku
    assert link.is_preferred
  end

  test "update removes a supplier via _destroy" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    supplier = create_supplier(organization: org)
    link = PartSupplier.create!(part: part, supplier: supplier)

    sign_in user
    assert_difference -> { part.part_suppliers.count }, -1 do
      patch part_path(part), params: { part: {
        name: part.name, category_id: part.category_id,
        part_suppliers_attributes: [ { id: link.id, _destroy: true } ]
      } }
    end
  end

  test "update returns to the referring page so the edit modal flow stays put" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)

    sign_in user
    patch part_path(part),
      params: { part: { name: "Renamed", category_id: part.category_id } },
      headers: { "Referer" => parts_url }

    assert_redirected_to parts_url
    assert_equal "Renamed", part.reload.name
  end

  test "create never links a tag from another organization" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    foreign_tag = create_tag(organization: create_organization, name: "foreign")

    sign_in user
    post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id, tag_ids: [ foreign_tag.id ] } }

    part = org.parts.find_by!(name: "Resistor 10k")
    assert_empty part.tags
    assert_not PartTag.exists?(tag: foreign_tag)
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

  test "import matches an existing part's mpn regardless of case" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    part = create_part(organization: org, category: category, name: "Old name", mpn: "RES-10K")

    csv = <<~CSV
      Name,Category,MPN
      Resistor 10k,Resistors,res-10k
    CSV

    sign_in user
    assert_no_difference "Part.count" do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    assert_match(/0 created, 1 updated, 0 skipped/, flash[:notice])
    assert_equal "Resistor 10k", part.reload.name
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

  test "import skips a row the ledger refuses without leaving a half-imported part" do
    user = create_user
    org = user.organizations.first

    csv = <<~CSV
      Name,Category,MPN,Location,Quantity
      Good part,Resistors,GOOD-1,Shelf,10
      Bad stock,Resistors,BAD-1,Shelf,-5
    CSV

    sign_in user
    post import_parts_path, params: { file: csv_upload(csv) }

    assert_redirected_to parts_path
    assert_match(/1 created, 0 updated, 1 skipped/, flash[:notice])
    assert org.parts.exists?(mpn: "GOOD-1")
    assert_not org.parts.exists?(mpn: "BAD-1"), "the part of a refused row must be rolled back too"
  end

  test "import reads a French Excel export saved as Windows-1252" do
    user = create_user
    org = user.organizations.first
    csv = "Désignation;Catégorie;MPN;Quantité;Emplacement\r\nRésistance 10k;Résistances;RC-10K;12;Étagère A\r\n"

    sign_in user
    post import_parts_path, params: { file: csv_upload(csv.encode("Windows-1252").b) }

    assert_match(/1 created/, flash[:notice])
    part = org.parts.find_by!(mpn: "RC-10K")
    assert_equal "Résistance 10k", part.name
    assert_equal "Résistances", part.category.name
    assert_equal 12, part.total_quantity
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

  test "import reconciles stock through the ledger as an adjustment, not a direct write" do
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
    assert_difference -> { StockMovement.where(part: part).count } => 1 do
      post import_parts_path, params: { file: csv_upload(csv) }
    end

    movement = StockMovement.where(part: part).order(:created_at, :id).last
    assert_equal "adjustment", movement.movement_type
    assert_equal 35, movement.quantity_delta
    assert_equal "Import", movement.reason
    assert_equal 40, PartStorage.find_by(part: part, storage_location: location).quantity
  end

  test "import records no movement when the sheet quantity already matches stock" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    location = create_storage_location(organization: org, name: "Existing Shelf")
    part = create_part(organization: org, category: category, mpn: "RES-10K")
    PartStorage.create!(part: part, storage_location: location, quantity: 40)

    csv = <<~CSV
      Name,Category,MPN,Location,Quantity
      Resistor 10k,Resistors,RES-10K,Existing Shelf,40
    CSV

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post import_parts_path, params: { file: csv_upload(csv) }
    end
  end

  test "import keeps an existing part's fields the sheet doesn't state" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    part = create_part(
      organization: org, category: category, name: "Old name", mpn: "RES-10K", sku: "SKU-1",
      manufacturer: "Yageo", value: "10k", package_type: "0603", unit_price: 0.1,
      min_stock_threshold: 50, status: "discontinued"
    )

    # No SKU/manufacturer/price/threshold/status columns, and a blank Value cell.
    csv = <<~CSV
      Name,Category,MPN,Value
      Resistor 10k,Resistors,RES-10K,
    CSV

    sign_in user
    post import_parts_path, params: { file: csv_upload(csv) }

    part.reload
    assert_equal "Resistor 10k", part.name
    assert_equal "SKU-1", part.sku
    assert_equal "Yageo", part.manufacturer
    assert_equal "10k", part.value
    assert_equal "0603", part.package_type
    assert_equal 0.1, part.unit_price.to_f
    assert_equal 50, part.min_stock_threshold
    assert_equal "discontinued", part.status
  end

  test "import updates an existing part's fields the sheet does state" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    part = create_part(organization: org, category: category, mpn: "RES-10K", unit_price: 0.1, min_stock_threshold: 50)

    csv = <<~CSV
      Name;Category;MPN;Unit Price;Min;Status
      Resistor 10k;Resistors;RES-10K;0,25;10;obsolete
    CSV

    sign_in user
    post import_parts_path, params: { file: csv_upload(csv) }

    part.reload
    assert_equal 0.25, part.unit_price.to_f
    assert_equal 10, part.min_stock_threshold
    assert_equal "obsolete", part.status
  end

  test "import with a location but no quantity leaves that location's stock alone" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors")
    location = create_storage_location(organization: org, name: "Shelf A")
    part = create_part(organization: org, category: category, mpn: "RES-10K")
    StockMovement.create!(organization: org, part: part, storage_location: location, movement_type: "in", quantity_delta: 40)

    csv = <<~CSV
      Name,Category,MPN,Location
      Resistor 10k,Resistors,RES-10K,Shelf A
    CSV

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post import_parts_path, params: { file: csv_upload(csv) }
    end
    assert_equal 40, part.reload.total_quantity
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

  test "create downloads the datasheet but hotlinks the supplier image URL" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    sign_in user

    download = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("%PDF-1.4 fake"), filename: "ds.pdf", content_type: "application/pdf"
    )

    # Only the datasheet is fetched server-side. Mouser's image CDN blocks
    # server-side downloads, so the image URL is stored and hotlinked instead.
    perform_enqueued_jobs do
      stub_singleton(SupplierCatalog::RemoteFile, :download, ->(*, **) { download }) do
        post parts_path, params: {
          part: { name: "Resistor 10k", category_id: category.id },
          datasheet_url: "https://www.mouser.com/ds.pdf",
          image_url: "https://www.mouser.com/img.png"
        }
      end
    end

    part = org.parts.find_by(name: "Resistor 10k")
    assert part.datasheet.attached?
    refute part.images.attached?, "supplier image is hotlinked, not downloaded"
    assert_equal "https://www.mouser.com/img.png", part.image_source_url
  end

  test "create exposes the hotlinked image as the thumbnail immediately" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    sign_in user

    # No download stub and no jobs: nothing is fetched for the image.
    post parts_path, params: {
      part: { name: "Resistor 10k", category_id: category.id },
      image_url: "https://www.mouser.com/img.png"
    }

    part = org.parts.find_by(name: "Resistor 10k")
    refute part.images.attached?
    assert_equal "https://www.mouser.com/img.png", part.image_source_url

    get parts_path
    part_json = inertia_props["parts"].find { |p| p["id"] == part.id }
    assert_equal "https://www.mouser.com/img.png", part_json["thumbnail_url"]
  end

  test "create attaches an uploaded image and it takes precedence over the supplier URL" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    sign_in user

    uploaded = Rack::Test::UploadedFile.new(
      StringIO.new("real-png-bytes"), "image/png", original_filename: "photo.png"
    )

    post parts_path, params: {
      part: { name: "Resistor 10k", category_id: category.id, images: [ uploaded ] },
      image_url: "https://www.mouser.com/img.png"
    }

    part = org.parts.find_by(name: "Resistor 10k")
    assert part.images.attached?, "uploaded image should attach"

    get parts_path
    part_json = inertia_props["parts"].find { |p| p["id"] == part.id }
    # The uploaded blob wins over the hotlink: a local, member-only file URL,
    # not the Mouser URL.
    assert_match %r{\A/files/}, part_json["thumbnail_url"]
    refute_equal "https://www.mouser.com/img.png", part_json["thumbnail_url"]
  end

  test "update downloads the datasheet but hotlinks the supplier image URL" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    sign_in user

    download = SupplierCatalog::RemoteFile::Download.new(
      io: StringIO.new("%PDF-1.4 fake"), filename: "ds.pdf", content_type: "application/pdf"
    )

    perform_enqueued_jobs do
      stub_singleton(SupplierCatalog::RemoteFile, :download, ->(*, **) { download }) do
        patch part_path(part), params: {
          part: { name: part.name, category_id: part.category_id },
          datasheet_url: "https://www.mouser.com/ds.pdf",
          image_url: "https://www.mouser.com/img.png"
        }
      end
    end

    part.reload
    assert part.datasheet.attached?
    refute part.images.attached?
    assert_equal "https://www.mouser.com/img.png", part.image_source_url
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

  test "bulk_destroy deletes only the organization's selected parts" do
    user = create_user
    org = user.organizations.first
    keep = create_part(organization: org, name: "Keep")
    doomed = [ create_part(organization: org, name: "Doomed A"), create_part(organization: org, name: "Doomed B") ]
    foreign = create_part(organization: create_organization, name: "Foreign")

    sign_in user
    assert_difference -> { Part.count } => -2 do
      delete bulk_destroy_parts_path, params: { part_ids: doomed.map(&:id) + [ foreign.id ] }
    end

    assert_redirected_to parts_path
    assert Part.exists?(keep.id)
    assert Part.exists?(foreign.id), "must not touch another organization's parts"
    doomed.each { |part| refute Part.exists?(part.id) }
  end

  test "bulk_destroy skips parts with stock history and reports the count" do
    user = create_user
    org = user.organizations.first
    location = create_storage_location(organization: org)
    clean = create_part(organization: org, name: "Clean")
    with_history = create_part(organization: org, name: "With History")
    StockMovement.create!(
      organization: org, part: with_history, storage_location: location, user: user,
      movement_type: "in", quantity_delta: 10
    )

    sign_in user
    assert_difference -> { Part.count } => -1 do
      delete bulk_destroy_parts_path, params: { part_ids: [ clean.id, with_history.id ] }
    end

    assert_redirected_to parts_path
    follow_redirect!
    refute Part.exists?(clean.id)
    assert Part.exists?(with_history.id)
    assert_match(/1 part deleted successfully/i, flash[:notice])
    assert_match(/1 part could not be deleted/i, flash[:notice])
  end

  test "bulk_destroy redirects with an alert when nothing is selected" do
    user = create_user
    sign_in user

    delete bulk_destroy_parts_path, params: { part_ids: [] }
    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/select at least one part/i, flash[:alert])
    assert_match(/select at least one part/i, inertia_props["errors"]["base"])
  end

  test "bulk_move redirects with an alert when no destination is chosen" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post bulk_move_parts_path, params: { part_ids: [ part.id ], storage_location_id: "" }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a destination/i, flash[:alert])
    assert_match(/choose a destination/i, inertia_props["errors"]["base"])
  end

  test "bulk_move rejects a destination from another organization" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    foreign_location = create_storage_location(organization: create_organization)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post bulk_move_parts_path, params: { part_ids: [ part.id ], storage_location_id: foreign_location.id }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a destination/i, flash[:alert])
    assert_match(/choose a destination/i, inertia_props["errors"]["base"])
  end

  test "bulk_move relocates all stock into the destination via ledger movements" do
    user = create_user
    org = user.organizations.first
    source_a = create_storage_location(organization: org, name: "Drawer A")
    source_b = create_storage_location(organization: org, name: "Bin B")
    destination = create_storage_location(organization: org, name: "Shelf C")
    part = create_part(organization: org)
    PartStorage.create!(part: part, storage_location: source_a, quantity: 40)
    PartStorage.create!(part: part, storage_location: source_b, quantity: 10)

    sign_in user
    # Two sources → an out+in pair each.
    assert_difference -> { StockMovement.count } => 4 do
      post bulk_move_parts_path, params: { part_ids: [ part.id ], storage_location_id: destination.id }
    end

    assert_redirected_to parts_path
    assert_equal 0, PartStorage.find_by(part: part, storage_location: source_a).quantity
    assert_equal 0, PartStorage.find_by(part: part, storage_location: source_b).quantity
    assert_equal 50, PartStorage.find_by(part: part, storage_location: destination).quantity
    assert_equal 50, part.total_quantity
  end

  test "bulk_move rolls a part back and reports it unmoved when a movement fails" do
    user = create_user
    org = user.organizations.first
    source = create_storage_location(organization: org, name: "Drawer A")
    destination = create_storage_location(organization: org, name: "Shelf C")
    part = create_part(organization: org)
    PartStorage.create!(part: part, storage_location: source, quantity: 40)

    # Let the "out" through, then fail the matching "in" (as stock changed by
    # another request would).
    calls = 0
    original = PartStorage.method(:find_or_create_by!)
    flaky = lambda do |*args, **kwargs, &blk|
      calls += 1
      raise ActiveRecord::RecordInvalid, PartStorage.new if calls == 2
      original.call(*args, **kwargs, &blk)
    end

    sign_in user
    stub_singleton(PartStorage, :find_or_create_by!, flaky) do
      assert_no_difference -> { StockMovement.count } do
        post bulk_move_parts_path, params: { part_ids: [ part.id ], storage_location_id: destination.id }
      end
    end

    assert_redirected_to parts_path
    assert_match(/for 0 parts/, flash[:notice])
    assert_equal 40, PartStorage.find_by(part: part, storage_location: source).quantity
  end

  test "bulk_move leaves stock already in the destination untouched" do
    user = create_user
    org = user.organizations.first
    source = create_storage_location(organization: org, name: "Drawer A")
    destination = create_storage_location(organization: org, name: "Shelf C")
    part = create_part(organization: org)
    PartStorage.create!(part: part, storage_location: source, quantity: 30)
    PartStorage.create!(part: part, storage_location: destination, quantity: 5)

    sign_in user
    assert_difference -> { StockMovement.count } => 2 do
      post bulk_move_parts_path, params: { part_ids: [ part.id ], storage_location_id: destination.id }
    end

    assert_equal 0, PartStorage.find_by(part: part, storage_location: source).quantity
    assert_equal 35, PartStorage.find_by(part: part, storage_location: destination).quantity
  end

  test "bulk_update_category sets the category on only the selected parts" do
    user = create_user
    org = user.organizations.first
    old_category = create_category(organization: org)
    new_category = create_category(organization: org, name: "Resistors")
    part_a = create_part(organization: org, category: old_category)
    part_b = create_part(organization: org, category: old_category)
    untouched = create_part(organization: org, category: old_category)

    sign_in user
    post bulk_update_category_parts_path, params: { part_ids: [ part_a.id, part_b.id ], category_id: new_category.id }

    assert_redirected_to parts_path
    assert_equal new_category.id, part_a.reload.category_id
    assert_equal new_category.id, part_b.reload.category_id
    assert_equal old_category.id, untouched.reload.category_id
  end

  test "bulk_update_category rejects a category from another organization" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    foreign_category = create_category(organization: create_organization)

    sign_in user
    post bulk_update_category_parts_path, params: { part_ids: [ part.id ], category_id: foreign_category.id }

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a category/i, flash[:alert])
    assert_equal part.category_id, part.reload.category_id
    assert_match(/choose a category/i, inertia_props["errors"]["base"])
  end

  test "bulk_update_status sets the lifecycle status on the selected parts" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, status: "active")

    sign_in user
    post bulk_update_status_parts_path, params: { part_ids: [ part.id ], status: "discontinued" }

    assert_redirected_to parts_path
    assert_equal "discontinued", part.reload.status
  end

  test "bulk_update_status rejects an invalid status value" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org, status: "active")

    sign_in user
    post bulk_update_status_parts_path, params: { part_ids: [ part.id ], status: "vaporized" }

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/valid status/i, flash[:alert])
    assert_equal "active", part.reload.status
    assert_match(/valid status/i, inertia_props["errors"]["base"])
  end

  test "bulk_update_tags adds tags without duplicating existing links" do
    user = create_user
    org = user.organizations.first
    tag_a = create_tag(organization: org)
    tag_b = create_tag(organization: org)
    part = create_part(organization: org)
    part.part_tags.create!(tag: tag_a)

    sign_in user
    assert_difference -> { PartTag.count } => 1 do
      post bulk_update_tags_parts_path, params: { part_ids: [ part.id ], tag_ids: [ tag_a.id, tag_b.id ], mode: "add" }
    end

    assert_redirected_to parts_path
    assert_equal [ tag_a.id, tag_b.id ].sort, part.reload.tag_ids.sort
  end

  test "bulk_update_tags removes tags in remove mode" do
    user = create_user
    org = user.organizations.first
    tag_a = create_tag(organization: org)
    tag_b = create_tag(organization: org)
    part = create_part(organization: org)
    part.part_tags.create!(tag: tag_a)
    part.part_tags.create!(tag: tag_b)

    sign_in user
    assert_difference -> { PartTag.count } => -1 do
      post bulk_update_tags_parts_path, params: { part_ids: [ part.id ], tag_ids: [ tag_a.id ], mode: "remove" }
    end

    assert_redirected_to parts_path
    assert_equal [ tag_b.id ], part.reload.tag_ids
  end

  test "bulk_update_tags adds only the missing links across multiple parts" do
    user = create_user
    org = user.organizations.first
    tag_a = create_tag(organization: org)
    tag_b = create_tag(organization: org)
    part_with_a = create_part(organization: org)
    part_with_a.part_tags.create!(tag: tag_a)
    bare_part = create_part(organization: org)

    sign_in user
    # part_with_a is only missing tag_b, bare_part is missing both.
    assert_difference -> { PartTag.count } => 3 do
      post bulk_update_tags_parts_path,
        params: { part_ids: [ part_with_a.id, bare_part.id ], tag_ids: [ tag_a.id, tag_b.id ], mode: "add" }
    end

    assert_equal [ tag_a.id, tag_b.id ].sort, part_with_a.reload.tag_ids.sort
    assert_equal [ tag_a.id, tag_b.id ].sort, bare_part.reload.tag_ids.sort
  end

  test "bulk_update_tags redirects with an alert when no tag is chosen" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)

    sign_in user
    assert_no_difference -> { PartTag.count } do
      post bulk_update_tags_parts_path, params: { part_ids: [ part.id ], tag_ids: [], mode: "add" }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose at least one tag/i, flash[:alert])
    assert_match(/choose at least one tag/i, inertia_props["errors"]["base"])
  end

  test "bulk_assign_supplier links and prefers the supplier for the selected parts" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org)
    part = create_part(organization: org)

    sign_in user
    post bulk_assign_supplier_parts_path, params: { part_ids: [ part.id ], supplier_id: supplier.id }

    assert_redirected_to parts_path
    link = part.reload.part_suppliers.find_by(supplier: supplier)
    assert link.present?
    assert link.is_preferred?
  end

  test "bulk_assign_supplier assigns nothing when one link can't be saved" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org)
    good = create_part(organization: org)
    broken = create_part(organization: org)
    link = PartSupplier.create!(part: broken, supplier: supplier)
    link.update_column(:url, "not a url") # invalid, so saving it again fails

    sign_in user
    post bulk_assign_supplier_parts_path, params: { part_ids: [ good.id, broken.id ], supplier_id: supplier.id }

    assert_redirected_to parts_path
    assert_match(/no supplier was assigned/i, flash[:alert])
    assert_not good.reload.part_suppliers.exists?(supplier: supplier)
  end

  test "bulk_assign_supplier demotes a previously preferred supplier" do
    user = create_user
    org = user.organizations.first
    old_supplier = create_supplier(organization: org, name: "Old Supplier")
    new_supplier = create_supplier(organization: org, name: "New Supplier")
    part = create_part(organization: org)
    part.part_suppliers.create!(supplier: old_supplier, is_preferred: true)

    sign_in user
    post bulk_assign_supplier_parts_path, params: { part_ids: [ part.id ], supplier_id: new_supplier.id }

    assert_redirected_to parts_path
    refute part.part_suppliers.find_by(supplier: old_supplier).is_preferred?
    assert part.part_suppliers.find_by(supplier: new_supplier).is_preferred?
  end

  test "bulk_assign_supplier rejects a supplier from another organization" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    foreign_supplier = create_supplier(organization: create_organization)

    sign_in user
    assert_no_difference -> { PartSupplier.count } do
      post bulk_assign_supplier_parts_path, params: { part_ids: [ part.id ], supplier_id: foreign_supplier.id }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a supplier/i, flash[:alert])
    assert_match(/choose a supplier/i, inertia_props["errors"]["base"])
  end

  test "bulk_assign_supplier redirects with an alert when no supplier is chosen" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)

    sign_in user
    assert_no_difference -> { PartSupplier.count } do
      post bulk_assign_supplier_parts_path, params: { part_ids: [ part.id ], supplier_id: "" }
    end

    assert_redirected_to parts_path
    follow_redirect!
    assert_match(/choose a supplier/i, flash[:alert])
    assert_match(/choose a supplier/i, inertia_props["errors"]["base"])
  end

  test "update ignores tags from another organization" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    own_tag = create_tag(organization: org, name: "own")
    foreign_tag = create_tag(organization: create_user.organizations.first, name: "foreign")

    sign_in user
    patch part_path(part), params: { part: { name: part.name, category_id: part.category_id, tag_ids: [ own_tag.id, foreign_tag.id ] } }

    assert_response :redirect
    assert_equal [ own_tag ], part.reload.tags
  end

  test "a rejected update keeps the part's previous tags" do
    user = create_user
    org = user.organizations.first
    part = create_part(organization: org)
    old_tag = create_tag(organization: org, name: "old")
    part.tags << old_tag

    sign_in user
    patch part_path(part), params: { part: { name: "", category_id: part.category_id, tag_ids: [ create_tag(organization: org, name: "new").id ] } }

    assert_equal [ old_tag ], part.reload.tags
  end

  private

  def csv_upload(content)
    file = Tempfile.new([ "import", ".csv" ], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

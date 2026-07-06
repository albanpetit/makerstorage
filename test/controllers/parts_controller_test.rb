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

  test "index passes through the search query param as initial_query" do
    user = create_user
    sign_in user

    get parts_path(search: "resistor")
    assert_response :success
    assert_equal "resistor", inertia_props["initial_query"]
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

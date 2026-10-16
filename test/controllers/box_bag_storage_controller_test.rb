require "test_helper"

# Box & bag numbering through the parts, zones and settings controllers.
class BoxBagStorageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(ipn_generation_mode: "box_bag")
    @box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    @category = create_category(organization: @org)
    sign_in @user
  end

  test "add_bags appends numbered bags to a box" do
    @box.add_bags!(2)

    assert_difference -> { @box.children.bags.count } => 3 do
      post add_bags_storage_location_path(@box), params: { count: 3 }
    end

    assert_redirected_to storage_locations_path(zone: @box.id)
    assert_equal %w[A-1 A-2 A-3 A-4 A-5], @box.children.bags.order(:position).pluck(:code)
    assert_includes flash[:notice], "A-3 to A-5"
  end

  test "add_bags refuses a zone that isn't a box, and silly counts" do
    shelf = create_storage_location(organization: @org, location_type: "shelf")

    assert_no_difference -> { StorageLocation.count } do
      post add_bags_storage_location_path(shelf), params: { count: 2 }
      post add_bags_storage_location_path(@box), params: { count: 0 }
      post add_bags_storage_location_path(@box), params: { count: 10_000 }
    end
  end

  test "add_bags can't reach another organization's box" do
    foreign_box = create_storage_location(organization: create_organization, location_type: "box", code: "A")

    post add_bags_storage_location_path(foreign_box), params: { count: 2 }

    assert_response :not_found
    assert_equal 0, foreign_box.children.count
  end

  test "add_bags is refused to a viewer" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer

    assert_no_difference -> { StorageLocation.count } do
      post add_bags_storage_location_path(@box), params: { count: 2 }
    end
  end

  test "create puts a new part and its opening stock in the first free bag" do
    bag = @box.add_bags!(1).first

    post parts_path, params: { part: { name: "Resistor 10k", category_id: @category.id }, initial_quantity: "12" }

    part = Part.find_by!(name: "Resistor 10k")
    assert_equal "A-1", part.ipn
    assert_equal bag, part.bag
    assert_equal 12, PartStorage.find_by!(part: part, storage_location: bag).quantity
  end

  test "create with opening stock on a shelf leaves the bags free" do
    bag = @box.add_bags!(1).first
    shelf = create_storage_location(organization: @org, name: "Shelf", location_type: "shelf")

    post parts_path, params: { part: { name: "Resistor 10k", category_id: @category.id }, initial_quantity: "12", initial_location_id: shelf.id }

    part = Part.find_by!(name: "Resistor 10k")
    assert_nil part.bag
    assert_nil part.ipn
    assert_equal [ bag ], @org.free_bags.to_a
  end

  test "create with opening stock in a bag takes that bag" do
    _first, second = @box.add_bags!(2)

    post parts_path, params: { part: { name: "Resistor 10k", category_id: @category.id }, initial_quantity: "12", initial_location_id: second.id }

    part = Part.find_by!(name: "Resistor 10k")
    assert_equal second, part.bag
    assert_equal "A-2", part.ipn
    assert_equal 12, PartStorage.find_by!(part: part, storage_location: second).quantity
  end

  test "import doesn't hand out bags to rows stocked elsewhere, and takes a bag the row names" do
    bag1, bag2 = @box.add_bags!(2)
    create_storage_location(organization: @org, name: "Shelf", location_type: "shelf")
    csv = <<~CSV
      Name,Category,Location,Quantity
      Resistor 10k,#{@category.name},Shelf,40
      Cap 100n,#{@category.name},A-2,10
      Diode,#{@category.name},,
    CSV

    post import_parts_path, params: { file: csv_upload(csv) }

    assert_nil Part.find_by!(name: "Resistor 10k").bag
    assert_nil Part.find_by!(name: "Diode").bag
    cap = Part.find_by!(name: "Cap 100n")
    assert_equal bag2, cap.bag
    assert_equal "A-2", cap.ipn
    assert_equal 10, PartStorage.find_by!(part: cap, storage_location: bag2).quantity
    assert_equal [ bag1 ], @org.free_bags.to_a
  end

  test "import skips a row whose stock would land in another part's bag" do
    bag = @box.add_bags!(1).first
    holder = create_part(organization: @org, category: @category)
    csv = <<~CSV
      Name,Category,Location,Quantity
      Cap 100n,#{@category.name},A-1,10
    CSV

    post import_parts_path, params: { file: csv_upload(csv) }

    assert_nil Part.find_by(name: "Cap 100n")
    assert_equal bag, holder.reload.bag
    assert_not PartStorage.where(storage_location: bag).where("quantity > 0").exists?
  end

  test "create takes the chosen bag and ignores a typed IPN" do
    _first, second = @box.add_bags!(2)

    post parts_path, params: { part: { name: "Cap 100n", category_id: @category.id, bag_id: second.id, ipn: "X-1" } }

    assert_equal "A-2", Part.find_by!(name: "Cap 100n").ipn
  end

  test "update moves a part to another bag along with its stock" do
    bag1, bag2 = @box.add_bags!(2)
    part = create_part(organization: @org, category: @category)
    @org.stock_movements.create!(part: part, storage_location: bag1, movement_type: "in", quantity_delta: 7)

    patch part_path(part), params: { part: { bag_id: bag2.id } }

    assert_equal "A-2", part.reload.ipn
    assert_equal 0, PartStorage.find_by!(part: part, storage_location: bag1).quantity
    assert_equal 7, PartStorage.find_by!(part: part, storage_location: bag2).quantity
  end

  test "update refuses a bag another part holds" do
    bag1, bag2 = @box.add_bags!(2)
    part = create_part(organization: @org, category: @category)
    create_part(organization: @org, category: @category)

    patch part_path(part), params: { part: { bag_id: bag2.id } }

    assert_equal bag1, part.reload.bag
  end

  test "bag_id is ignored outside box & bag mode" do
    bag = @box.add_bags!(1).first
    @org.update!(ipn_generation_mode: "incremental")

    post parts_path, params: { part: { name: "Diode", category_id: @category.id, bag_id: bag.id } }

    assert_nil Part.find_by!(name: "Diode").bag
  end

  test "the parts list and detail offer the free bags plus the part's own" do
    bag1, bag2 = @box.add_bags!(2)
    part = create_part(organization: @org, category: @category)

    get parts_path
    assert_equal [ { "id" => bag2.id, "code" => "A-2" } ], inertia_props["bag_options"]

    get edit_part_path(part, format: :json)
    assert_equal [ bag1.id, bag2.id ], response.parsed_body["bag_options"].map { |bag| bag["id"] }
    assert_equal bag1.id, response.parsed_body["part"]["bag_id"]
  end

  test "settings show the free bags" do
    @box.add_bags!(2)

    get settings_path

    organization = inertia_props["organization"]
    assert_equal 2, organization["free_bags_count"]
    assert_equal %w[A-1 A-2], organization["free_bag_codes"]
  end

  test "reassign_ipns in box & bag mode gives stocked parts their bag" do
    bag = @box.add_bags!(1).first
    @org.update!(ipn_generation_mode: "manual")
    part = create_part(organization: @org, category: @category, ipn: "OLD-1")
    @org.stock_movements.create!(part: part, storage_location: bag, movement_type: "in", quantity_delta: 3)
    @org.update!(ipn_generation_mode: "box_bag")

    post reassign_ipns_settings_path

    assert_equal "A-1", part.reload.ipn
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  def csv_upload(content)
    file = Tempfile.new([ "import", ".csv" ], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end
end

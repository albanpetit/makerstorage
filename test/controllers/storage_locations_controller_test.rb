require "test_helper"

class StorageLocationsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get storage_locations_path
    assert_redirected_to new_user_session_path
  end

  test "renders zones, part storages, and recent movements for the current organization" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Workshop", location_type: "room")
    shelf = create_storage_location(organization: org, name: "Shelf A", location_type: "shelf", parent: room)
    category = create_category(organization: org)
    part = create_part(organization: org, category: category, mpn: "RES-10K")
    PartStorage.create!(part: part, storage_location: shelf, quantity: 25)

    sign_in user
    get storage_locations_path
    assert_response :success

    props = inertia_props
    location_json = props["storage_locations"].find { |l| l["id"] == shelf.id }
    assert_equal "Shelf A", location_json["name"]
    assert_equal room.id, location_json["parent_id"]

    part_storage_json = props["part_storages"].find { |ps| ps["location_id"] == shelf.id }
    assert_equal 25, part_storage_json["quantity"]
    assert_equal "RES-10K", part_storage_json["part"]["reference"]
  end

  test "does not leak another organization's zones" do
    user = create_user
    other_org = create_organization
    create_storage_location(organization: other_org, name: "Someone else's shelf")

    sign_in user
    get storage_locations_path
    assert_response :success

    names = inertia_props["storage_locations"].map { |l| l["name"] }
    assert_not_includes names, "Someone else's shelf"
  end

  test "create builds a zone under a parent" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Workshop", location_type: "room")

    sign_in user
    assert_difference -> { StorageLocation.count } => 1 do
      post storage_locations_path, params: {
        storage_location: { name: "Shelf B", location_type: "shelf", parent_id: room.id }
      }
    end

    assert_redirected_to storage_locations_path
    zone = StorageLocation.find_by(name: "Shelf B")
    assert_equal room.id, zone.parent_id
  end

  test "create fails with a blank name" do
    user = create_user

    sign_in user
    assert_no_difference "StorageLocation.count" do
      post storage_locations_path, params: { storage_location: { name: "", location_type: "box" } }
    end

    assert_redirected_to storage_locations_path
  end

  test "update renames and reparents a zone" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Workshop", location_type: "room")
    other_room = create_storage_location(organization: org, name: "Storage room", location_type: "room")
    shelf = create_storage_location(organization: org, name: "Shelf A", location_type: "shelf", parent: room)

    sign_in user
    patch storage_location_path(shelf), params: {
      storage_location: { name: "Shelf A2", parent_id: other_room.id }
    }

    assert_redirected_to storage_locations_path
    shelf.reload
    assert_equal "Shelf A2", shelf.name
    assert_equal other_room.id, shelf.parent_id
  end

  test "destroy removes a leaf zone" do
    user = create_user
    org = user.organizations.first
    shelf = create_storage_location(organization: org, name: "Shelf A", location_type: "shelf")

    sign_in user
    assert_difference -> { StorageLocation.count } => -1 do
      delete storage_location_path(shelf)
    end

    assert_redirected_to storage_locations_path
  end

  test "destroy is blocked when the zone has sub-zones" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Workshop", location_type: "room")
    create_storage_location(organization: org, name: "Shelf A", location_type: "shelf", parent: room)

    sign_in user
    assert_no_difference "StorageLocation.count" do
      delete storage_location_path(room)
    end

    assert_redirected_to storage_locations_path
    follow_redirect!
    assert_match(/sub-zones/, flash[:alert])
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

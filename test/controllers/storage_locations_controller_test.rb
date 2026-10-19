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

  test "opens the zone named by the zone param, only within the organization" do
    user = create_user
    org = user.organizations.first
    drawer = create_storage_location(organization: org, name: "Drawer 3")
    foreign = create_storage_location(organization: create_organization)

    sign_in user
    get storage_locations_path, params: { zone: drawer.id }
    assert_equal drawer.id, inertia_props["selected_zone_id"]

    get storage_locations_path, params: { zone: foreign.id }
    assert_nil inertia_props["selected_zone_id"]

    get storage_locations_path
    assert_nil inertia_props["selected_zone_id"]
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

  test "create as JSON returns the new zone for the storage zone picker" do
    user = create_user
    org = user.organizations.first
    room = create_storage_location(organization: org, name: "Lab", location_type: "room")

    sign_in user
    post storage_locations_path, params: { storage_location: { name: "Box 3", location_type: "box", parent_id: room.id, code: "B3" } }, as: :json

    assert_response :created
    box = org.storage_locations.find_by!(name: "Box 3")
    assert_equal(
      { "id" => box.id, "name" => "Lab > Box 3", "short_name" => "Box 3", "parent_id" => room.id,
        "location_type" => "box", "code" => "B3" },
      response.parsed_body["storage_location"]
    )
  end

  test "create as JSON returns validation errors" do
    user = create_user
    org = user.organizations.first
    create_storage_location(organization: org, name: "Box A", code: "BA")

    sign_in user
    assert_no_difference -> { org.storage_locations.count } do
      post storage_locations_path, params: { storage_location: { name: "Box B", location_type: "box", code: "ba" } }, as: :json
    end

    assert_response :unprocessable_content
    assert_match(/already been taken/, response.parsed_body["errors"]["code"])
  end

  test "create as JSON is forbidden for a viewer" do
    owner = create_user
    org = owner.organizations.first
    viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")

    sign_in viewer
    post switch_organization_path(org)
    assert_no_difference -> { org.storage_locations.count } do
      post storage_locations_path, params: { storage_location: { name: "Sneaky", location_type: "box" } }, as: :json
    end
    assert_response :forbidden
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

  test "move_stock transfers a component's full stock between zones via the ledger" do
    user = create_user
    org = user.organizations.first
    from = create_storage_location(organization: org, name: "Shelf A")
    to = create_storage_location(organization: org, name: "Shelf B")
    part = create_part(organization: org, category: create_category(organization: org))
    PartStorage.create!(part: part, storage_location: from, quantity: 40)

    sign_in user
    assert_difference -> { StockMovement.count } => 2 do
      post move_stock_storage_locations_path, params: {
        from_location_id: from.id, to_location_id: to.id,
        moves: [ { part_id: part.id, quantity: 40 } ]
      }
    end

    assert_equal 0, PartStorage.find_by(part: part, storage_location: from).quantity
    assert_equal 40, PartStorage.find_by(part: part, storage_location: to).quantity
    assert_redirected_to storage_locations_path
    follow_redirect!
    assert_match(/Moved 1 component to Shelf B/, flash[:notice])
  end

  test "move_stock supports a partial quantity" do
    user = create_user
    org = user.organizations.first
    from = create_storage_location(organization: org, name: "Shelf A")
    to = create_storage_location(organization: org, name: "Shelf B")
    part = create_part(organization: org, category: create_category(organization: org))
    PartStorage.create!(part: part, storage_location: from, quantity: 40)

    sign_in user
    post move_stock_storage_locations_path, params: {
      from_location_id: from.id, to_location_id: to.id,
      moves: [ { part_id: part.id, quantity: 15 } ]
    }

    assert_equal 25, PartStorage.find_by(part: part, storage_location: from).quantity
    assert_equal 15, PartStorage.find_by(part: part, storage_location: to).quantity
  end

  test "move_stock moves several components at once" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    from = create_storage_location(organization: org, name: "Shelf A")
    to = create_storage_location(organization: org, name: "Shelf B")
    a = create_part(organization: org, category: category)
    b = create_part(organization: org, category: category)
    PartStorage.create!(part: a, storage_location: from, quantity: 10)
    PartStorage.create!(part: b, storage_location: from, quantity: 5)

    sign_in user
    post move_stock_storage_locations_path, params: {
      from_location_id: from.id, to_location_id: to.id,
      moves: [ { part_id: a.id, quantity: 10 }, { part_id: b.id, quantity: 5 } ]
    }

    assert_equal 10, PartStorage.find_by(part: a, storage_location: to).quantity
    assert_equal 5, PartStorage.find_by(part: b, storage_location: to).quantity
    follow_redirect!
    assert_match(/Moved 2 components to Shelf B/, flash[:notice])
  end

  test "move_stock is atomic: one invalid move rolls back the whole batch" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    from = create_storage_location(organization: org, name: "Shelf A")
    to = create_storage_location(organization: org, name: "Shelf B")
    a = create_part(organization: org, category: category)
    b = create_part(organization: org, category: category)
    PartStorage.create!(part: a, storage_location: from, quantity: 10)
    PartStorage.create!(part: b, storage_location: from, quantity: 5)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post move_stock_storage_locations_path, params: {
        from_location_id: from.id, to_location_id: to.id,
        moves: [ { part_id: a.id, quantity: 10 }, { part_id: b.id, quantity: 99 } ]
      }
    end

    # The valid first move must not have applied either.
    assert_equal 10, PartStorage.find_by(part: a, storage_location: from).quantity
    assert_nil PartStorage.find_by(part: a, storage_location: to)
    follow_redirect!
    assert_match(/only 5/, flash[:alert])
  end

  test "move_stock rejects moving to the same zone" do
    user = create_user
    org = user.organizations.first
    zone = create_storage_location(organization: org, name: "Shelf A")
    part = create_part(organization: org, category: create_category(organization: org))
    PartStorage.create!(part: part, storage_location: zone, quantity: 10)

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post move_stock_storage_locations_path, params: {
        from_location_id: zone.id, to_location_id: zone.id,
        moves: [ { part_id: part.id, quantity: 5 } ]
      }
    end
    follow_redirect!
    assert_match(/different destination/, flash[:alert])
  end

  test "move_stock will not touch another organization's zone" do
    user = create_user
    org = user.organizations.first
    from = create_storage_location(organization: org, name: "Shelf A")
    part = create_part(organization: org, category: create_category(organization: org))
    PartStorage.create!(part: part, storage_location: from, quantity: 10)
    other_zone = create_storage_location(organization: create_organization, name: "Not yours")

    sign_in user
    assert_no_difference -> { StockMovement.count } do
      post move_stock_storage_locations_path, params: {
        from_location_id: from.id, to_location_id: other_zone.id,
        moves: [ { part_id: part.id, quantity: 5 } ]
      }
    end
    follow_redirect!
    assert_match(/Unknown storage zone/, flash[:alert])
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

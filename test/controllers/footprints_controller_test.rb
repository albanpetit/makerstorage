require "test_helper"

class FootprintsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get footprints_path
    assert_redirected_to new_user_session_path
  end

  test "index serializes footprints with part counts" do
    user = create_user
    org = user.organizations.first
    footprint = create_footprint(organization: org, name: "0805", mounting_type: "SMD", description: "Chip resistor")
    create_part(organization: org, footprint: footprint)

    sign_in user
    get footprints_path
    assert_response :success

    footprint_json = inertia_props["footprints"].find { |f| f["id"] == footprint.id }
    assert_equal "0805", footprint_json["name"]
    assert_equal "SMD", footprint_json["mounting_type"]
    assert_equal "Chip resistor", footprint_json["description"]
    assert_equal 1, footprint_json["parts_count"]
    assert_equal Footprint::MOUNTING_TYPES, inertia_props["mounting_types"]
  end

  test "index does not leak another organization's footprints" do
    user = create_user
    other_org = create_organization
    create_footprint(organization: other_org, name: "Someone else's footprint")

    sign_in user
    get footprints_path
    assert_response :success

    names = inertia_props["footprints"].map { |f| f["name"] }
    assert_not_includes names, "Someone else's footprint"
  end

  test "create builds a footprint" do
    user = create_user

    sign_in user
    assert_difference -> { Footprint.count } => 1 do
      post footprints_path, params: { footprint: { name: "SOT-23", mounting_type: "SMD" } }
    end

    assert_redirected_to footprints_path
    assert Footprint.exists?(name: "SOT-23", mounting_type: "SMD")
  end

  test "create fails with a blank name" do
    user = create_user

    sign_in user
    assert_no_difference "Footprint.count" do
      post footprints_path, params: { footprint: { name: "" } }
    end

    assert_redirected_to footprints_path
  end

  test "create fails with an invalid mounting type" do
    user = create_user

    sign_in user
    assert_no_difference "Footprint.count" do
      post footprints_path, params: { footprint: { name: "BGA", mounting_type: "Bogus" } }
    end
  end

  test "update edits a footprint" do
    user = create_user
    org = user.organizations.first
    footprint = create_footprint(organization: org, name: "Old Name")

    sign_in user
    patch footprint_path(footprint), params: { footprint: { name: "DIP-8", mounting_type: "Through-hole" } }

    assert_redirected_to footprints_path
    assert_equal "DIP-8", footprint.reload.name
    assert_equal "Through-hole", footprint.mounting_type
  end

  test "destroy removes a footprint" do
    user = create_user
    org = user.organizations.first
    footprint = create_footprint(organization: org)

    sign_in user
    assert_difference -> { Footprint.count } => -1 do
      delete footprint_path(footprint)
    end

    assert_redirected_to footprints_path
  end

  test "destroy is blocked while parts reference the footprint" do
    user = create_user
    org = user.organizations.first
    footprint = create_footprint(organization: org)
    create_part(organization: org, footprint: footprint)

    sign_in user
    assert_no_difference "Footprint.count" do
      delete footprint_path(footprint)
    end

    assert_redirected_to footprints_path
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

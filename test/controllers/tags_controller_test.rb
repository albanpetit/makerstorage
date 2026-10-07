require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get tags_path
    assert_redirected_to new_user_session_path
  end

  test "index serializes tags with part counts" do
    user = create_user
    org = user.organizations.first
    tag = create_tag(organization: org, name: "RoHS", color: "#22C55E", description: "Lead-free")
    part = create_part(organization: org)
    part.tags << tag

    sign_in user
    get tags_path
    assert_response :success

    tag_json = inertia_props["tags"].find { |t| t["id"] == tag.id }
    assert_equal "RoHS", tag_json["name"]
    assert_equal "#22C55E", tag_json["color"]
    assert_equal "Lead-free", tag_json["description"]
    assert_equal 1, tag_json["parts_count"]
  end

  test "index does not leak another organization's tags" do
    user = create_user
    other_org = create_organization
    create_tag(organization: other_org, name: "Someone else's tag")

    sign_in user
    get tags_path
    assert_response :success

    names = inertia_props["tags"].map { |t| t["name"] }
    assert_not_includes names, "Someone else's tag"
  end

  test "create builds a tag" do
    user = create_user

    sign_in user
    assert_difference -> { Tag.count } => 1 do
      post tags_path, params: { tag: { name: "favorite", color: "#3B82F6" } }
    end

    assert_redirected_to tags_path
    assert Tag.exists?(name: "favorite", color: "#3B82F6")
  end

  test "create scopes the tag to the current organization" do
    user = create_user
    org = user.organizations.first

    sign_in user
    post tags_path, params: { tag: { name: "obsolete" } }

    assert_equal org, Tag.find_by(name: "obsolete").organization
  end

  test "create fails with a blank name" do
    user = create_user

    sign_in user
    assert_no_difference "Tag.count" do
      post tags_path, params: { tag: { name: "" } }
    end

    assert_redirected_to tags_path
  end

  test "create fails with an invalid color" do
    user = create_user

    sign_in user
    assert_no_difference "Tag.count" do
      post tags_path, params: { tag: { name: "bad", color: "not-a-hex" } }
    end
  end

  test "update edits a tag" do
    user = create_user
    org = user.organizations.first
    tag = create_tag(organization: org, name: "Old Name")

    sign_in user
    patch tag_path(tag), params: { tag: { name: "smd", color: "#EF4444" } }

    assert_redirected_to tags_path
    assert_equal "smd", tag.reload.name
    assert_equal "#EF4444", tag.color
  end

  test "destroy removes a tag and its part associations but keeps the parts" do
    user = create_user
    org = user.organizations.first
    tag = create_tag(organization: org)
    part = create_part(organization: org)
    part.tags << tag

    sign_in user
    assert_difference -> { Tag.count } => -1, -> { PartTag.count } => -1 do
      delete tag_path(tag)
    end

    assert_redirected_to tags_path
    assert Part.exists?(part.id)
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

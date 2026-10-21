require "test_helper"

class PartDuplicatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @keep = create_part(organization: @org, category: @category, name: "NE555 timer", mpn: "NE555P")
    @duplicate = create_part(organization: @org, category: @category, name: "555", sku: "ne555p")
    @drawer = create_storage_location(organization: @org)
    @org.stock_movements.create!(part: @duplicate, storage_location: @drawer, movement_type: "in", quantity_delta: 3)
    sign_in @user
  end

  test "index lists the groups with each part's history and a suggested part to keep" do
    get part_duplicates_path

    assert_response :success
    group = inertia_props["groups"].sole
    assert_equal [ @keep.id, @duplicate.id ], group["parts"].map { |part| part["id"] }
    assert group["certain"]
    assert_equal @duplicate.id, group["suggested_keep_id"]
    assert_equal 1, group["parts"].last["movements_count"]
    assert_equal 3, group["parts"].last["total_quantity"]
    assert_equal 1, inertia_props["total_groups"]
    assert_not inertia_props["manual"]
  end

  test "index shows the parts picked in the inventory, only from this organization" do
    other = create_part(organization: @org, category: @category, name: "Unrelated")
    other_org = create_organization
    foreign = create_part(organization: other_org, category: create_category(organization: other_org))

    get part_duplicates_path(part_ids: [ @keep.id, other.id, foreign.id ])

    assert_response :success
    assert inertia_props["manual"]
    assert_equal [ @keep.id, other.id ], inertia_props["groups"].sole["parts"].map { |part| part["id"] }
  end

  test "the inventory shows how many duplicate groups there are" do
    get parts_path

    assert_equal 1, inertia_props["duplicate_groups_count"]
  end

  test "merge folds the duplicates into the kept part" do
    post merge_part_duplicates_path, params: { keep_id: @keep.id, part_ids: [ @duplicate.id ] }

    assert_redirected_to part_duplicates_path
    assert_not Part.exists?(@duplicate.id)
    assert_equal 3, @keep.reload.total_quantity
    assert_equal "Merged 1 part into NE555 timer. Moved 1 stock row and 1 movement.", flash[:notice]
  end

  test "merge from the inventory selection goes back to the inventory" do
    post merge_part_duplicates_path, params: { keep_id: @keep.id, part_ids: [ @duplicate.id ], return_to: "parts" }

    assert_redirected_to parts_path
  end

  test "merge reports a refused merge" do
    @duplicate.update!(unit: "meter")

    post merge_part_duplicates_path, params: { keep_id: @keep.id, part_ids: [ @duplicate.id ] }

    assert Part.exists?(@duplicate.id)
    assert_match "different units", flash[:alert]
  end

  test "merge can't reach another organization's parts" do
    other_org = create_organization
    foreign = create_part(organization: other_org, category: create_category(organization: other_org))

    post merge_part_duplicates_path, params: { keep_id: @keep.id, part_ids: [ foreign.id ] }
    assert Part.exists?(foreign.id)

    post merge_part_duplicates_path, params: { keep_id: foreign.id, part_ids: [ @duplicate.id ] }
    assert_response :not_found
    assert Part.exists?(@duplicate.id)
  end

  test "dismiss marks the group as not duplicates" do
    post dismiss_part_duplicates_path, params: { part_ids: [ @keep.id, @duplicate.id ] }

    assert_redirected_to part_duplicates_path
    assert PartDuplicateDismissal.exists?(part_id: @keep.id, other_part_id: @duplicate.id)
    assert_empty PartDuplicates.new(@org).groups
  end

  test "viewers see duplicates but can't merge or dismiss them" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    get part_duplicates_path
    assert_response :success

    post merge_part_duplicates_path, params: { keep_id: @keep.id, part_ids: [ @duplicate.id ] }
    post dismiss_part_duplicates_path, params: { part_ids: [ @keep.id, @duplicate.id ] }

    assert Part.exists?(@duplicate.id)
    assert_equal 0, PartDuplicateDismissal.count
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

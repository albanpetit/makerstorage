require "test_helper"

# Exercises the `verify_organization_writer` gate: viewers may read but never
# write, while members/admins/owners may write. Covers a representative sample
# of write endpoints plus the shared auth prop the UI gates on.
class RoleAuthorizationTest < ActionDispatch::IntegrationTest
  def setup
    @owner = create_user(email: "owner@example.com")
    @org = @owner.organizations.first
    @category = create_category(organization: @org)
    @location = create_storage_location(organization: @org)
    @part = create_part(organization: @org, category: @category)

    @viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: @org, user: @viewer, role: "viewer")

    @member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: @org, user: @member, role: "member")
  end

  # Makes `org` the signed-in user's current organization for the session.
  def act_as(user)
    sign_in user
    post "/organizations/#{@org.id}/switch"
  end

  test "viewer cannot create a supplier" do
    act_as @viewer
    assert_no_difference -> { Supplier.count } do
      post suppliers_path, params: { supplier: { name: "Mouser" } }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "member can create a supplier" do
    act_as @member
    assert_difference -> { Supplier.count } => 1 do
      post suppliers_path, params: { supplier: { name: "Mouser" } }
    end
  end

  test "viewer cannot create a tag" do
    act_as @viewer
    assert_no_difference -> { Tag.count } do
      post tags_path, params: { tag: { name: "nope" } }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "member can create a tag" do
    act_as @member
    assert_difference -> { Tag.count } => 1 do
      post tags_path, params: { tag: { name: "favorite" } }
    end
  end

  test "viewer cannot create a part" do
    act_as @viewer
    assert_no_difference -> { Part.count } do
      post parts_path, params: { part: { name: "New part", category_id: @category.id } }
    end
  end

  test "viewer cannot bulk-delete parts" do
    act_as @viewer
    assert_no_difference -> { Part.count } do
      delete bulk_destroy_parts_path, params: { part_ids: [ @part.id ] }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "viewer cannot bulk stock in/out" do
    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post bulk_stock_parts_path, params: {
        part_ids: [ @part.id ], storage_location_id: @location.id, movement_type: "in", quantity: "5"
      }
    end
  end

  test "viewer cannot bulk-move parts" do
    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post bulk_move_parts_path, params: { part_ids: [ @part.id ], storage_location_id: @location.id }
    end
  end

  test "viewer cannot create a stock movement" do
    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post stock_movements_path, params: {
        stock_movement: { part_id: @part.id, storage_location_id: @location.id, movement_type: "in", quantity: "5" }
      }
    end
  end

  test "viewer cannot create a storage location" do
    act_as @viewer
    assert_no_difference -> { StorageLocation.count } do
      post storage_locations_path, params: { storage_location: { name: "Bench", location_type: "bench" } }
    end
  end

  test "viewer cannot record a scanner movement" do
    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post scan_movements_path, params: {
        scan: { part_id: @part.id, storage_location_id: @location.id, quantity_delta: 3 }
      }
    end
  end

  test "shared auth prop marks a viewer read-only" do
    act_as @viewer
    get dashboard_props
    assert_equal false, auth_prop["is_organization_writer"]
    assert_equal "viewer", auth_prop["organization_role"]
  end

  test "shared auth prop marks a member as a writer" do
    act_as @member
    get dashboard_props
    assert_equal true, auth_prop["is_organization_writer"]
    assert_equal "member", auth_prop["organization_role"]
  end

  private

  def dashboard_props
    root_path
  end

  def auth_prop
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]["auth"]
  end
end

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
    @tag = create_tag(organization: @org)
    @supplier = create_supplier(organization: @org)

    @viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: @org, user: @viewer, role: "viewer")

    @member = create_user(email: "member@example.com")
    OrganizationMembership.create!(organization: @org, user: @member, role: "member")

    @admin = create_user(email: "admin@example.com")
    OrganizationMembership.create!(organization: @org, user: @admin, role: "admin")
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
    assert_match(/admin access/i, flash[:alert])
  end

  # Bulk delete is admin-gated (unlike the other bulk actions, which only
  # require the general writer role) because it's an irreversible, org-wide
  # mass deletion.
  test "member cannot bulk-delete parts" do
    act_as @member
    assert_no_difference -> { Part.count } do
      delete bulk_destroy_parts_path, params: { part_ids: [ @part.id ] }
    end
    assert_match(/admin access/i, flash[:alert])
  end

  test "admin can bulk-delete parts" do
    act_as @admin
    assert_difference -> { Part.count } => -1 do
      delete bulk_destroy_parts_path, params: { part_ids: [ @part.id ] }
    end
  end

  test "viewer cannot bulk-move parts" do
    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post bulk_move_parts_path, params: { part_ids: [ @part.id ], storage_location_id: @location.id }
    end
  end

  test "viewer cannot bulk-update part category" do
    act_as @viewer
    other_category = create_category(organization: @org)
    post bulk_update_category_parts_path, params: { part_ids: [ @part.id ], category_id: other_category.id }
    assert_match(/read-only/i, flash[:alert])
    assert_equal @category.id, @part.reload.category_id
  end

  test "member can bulk-update part category" do
    act_as @member
    other_category = create_category(organization: @org)
    post bulk_update_category_parts_path, params: { part_ids: [ @part.id ], category_id: other_category.id }
    assert_equal other_category.id, @part.reload.category_id
  end

  test "viewer cannot bulk-update part status" do
    act_as @viewer
    post bulk_update_status_parts_path, params: { part_ids: [ @part.id ], status: "discontinued" }
    assert_match(/read-only/i, flash[:alert])
    assert_equal "active", @part.reload.status
  end

  test "member can bulk-update part status" do
    act_as @member
    post bulk_update_status_parts_path, params: { part_ids: [ @part.id ], status: "discontinued" }
    assert_equal "discontinued", @part.reload.status
  end

  test "viewer cannot bulk-update part tags" do
    act_as @viewer
    assert_no_difference -> { PartTag.count } do
      post bulk_update_tags_parts_path, params: { part_ids: [ @part.id ], tag_ids: [ @tag.id ], mode: "add" }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "member can bulk-update part tags" do
    act_as @member
    assert_difference -> { PartTag.count } => 1 do
      post bulk_update_tags_parts_path, params: { part_ids: [ @part.id ], tag_ids: [ @tag.id ], mode: "add" }
    end
  end

  test "viewer cannot bulk-assign a supplier" do
    act_as @viewer
    assert_no_difference -> { PartSupplier.count } do
      post bulk_assign_supplier_parts_path, params: { part_ids: [ @part.id ], supplier_id: @supplier.id }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "member can bulk-assign a supplier" do
    act_as @member
    assert_difference -> { PartSupplier.count } => 1 do
      post bulk_assign_supplier_parts_path, params: { part_ids: [ @part.id ], supplier_id: @supplier.id }
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

  test "viewer cannot move stock between zones" do
    other = create_storage_location(organization: @org, name: "Shelf B")
    PartStorage.create!(part: @part, storage_location: @location, quantity: 10)

    act_as @viewer
    assert_no_difference -> { StockMovement.count } do
      post move_stock_storage_locations_path, params: {
        from_location_id: @location.id, to_location_id: other.id,
        moves: [ { part_id: @part.id, quantity: 5 } ]
      }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "member can move stock between zones" do
    other = create_storage_location(organization: @org, name: "Shelf B")
    PartStorage.create!(part: @part, storage_location: @location, quantity: 10)

    act_as @member
    assert_difference -> { StockMovement.count } => 2 do
      post move_stock_storage_locations_path, params: {
        from_location_id: @location.id, to_location_id: other.id,
        moves: [ { part_id: @part.id, quantity: 5 } ]
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

  test "a deactivated member can neither switch into nor write to the organization" do
    @org.organization_memberships.find_by(user: @member).deactivate!
    act_as @member

    assert_no_difference -> { @org.tags.count } do
      post tags_path, params: { tag: { name: "sneaky" } }
    end
    get tags_path
    assert_response :success
    assert_not_includes response.body, @tag.name
  end

  test "a user with no active membership anywhere lands on their profile, not a redirect loop" do
    personal = @member.organizations.find_by(personal: true)
    OrganizationMembership.create!(organization: personal, user: @owner, role: "owner")
    @member.organization_memberships.each(&:deactivate!)
    sign_in @member

    get root_path
    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_match(/not an active member/i, flash[:alert])
  end
end

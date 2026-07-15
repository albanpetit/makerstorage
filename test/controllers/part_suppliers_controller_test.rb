require "test_helper"

class PartSuppliersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = create_user
    @org = @user.organizations.first
    @part = create_part(organization: @org)
    @supplier = create_supplier(organization: @org)
  end

  test "create links a supplier to the part" do
    sign_in @user
    assert_difference -> { @part.part_suppliers.count } => 1 do
      post part_part_suppliers_path(@part), params: {
        part_supplier: { supplier_id: @supplier.id, unit_price: "1.50" }
      }
    end
    assert_redirected_to edit_part_path(@part)
  end

  test "create rejects a supplier from another organization" do
    other_supplier = create_supplier(organization: create_organization)
    sign_in @user
    assert_no_difference -> { PartSupplier.count } do
      post part_part_suppliers_path(@part), params: {
        part_supplier: { supplier_id: other_supplier.id }
      }
    end
    assert_match(/organization/i, flash[:alert])
  end

  test "set_preferred marks one link preferred and unsets the others" do
    first = PartSupplier.create!(part: @part, supplier: @supplier, is_preferred: true)
    second_supplier = create_supplier(organization: @org)
    second = PartSupplier.create!(part: @part, supplier: second_supplier)

    sign_in @user
    post set_preferred_part_part_supplier_path(@part, second)

    assert_redirected_to edit_part_path(@part)
    assert_not first.reload.is_preferred
    assert second.reload.is_preferred
  end

  test "destroy removes the link" do
    part_supplier = PartSupplier.create!(part: @part, supplier: @supplier)
    sign_in @user
    assert_difference -> { PartSupplier.count } => -1 do
      delete part_part_supplier_path(@part, part_supplier)
    end
    assert_redirected_to edit_part_path(@part)
  end

  test "cannot manage suppliers on another organization's part" do
    other_part = create_part(organization: create_organization)
    sign_in @user
    assert_no_difference -> { PartSupplier.count } do
      post part_part_suppliers_path(other_part), params: {
        part_supplier: { supplier_id: @supplier.id }
      }
    end
    assert_response :not_found
  end

  test "a viewer cannot link a supplier" do
    viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")

    sign_in viewer
    post "/organizations/#{@org.id}/switch"
    assert_no_difference -> { PartSupplier.count } do
      post part_part_suppliers_path(@part), params: {
        part_supplier: { supplier_id: @supplier.id }
      }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "redirects a signed-out visitor to login" do
    post part_part_suppliers_path(@part), params: { part_supplier: { supplier_id: @supplier.id } }
    assert_redirected_to new_user_session_path
  end
end

require "test_helper"

class SuppliersControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get suppliers_path
    assert_redirected_to new_user_session_path
  end

  test "index serializes linked components, lead time, stock value, and orders" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    supplier = create_supplier(organization: org, name: "Mouser")
    part = create_part(organization: org, category: category, mpn: "RES-10K", unit_price: 0.05)
    PartStorage.create!(part: part, storage_location: location, quantity: 200)
    PartSupplier.create!(part: part, supplier: supplier, lead_time_days: 6, unit_price: 0.04)
    purchase = Purchase.create!(organization: org, supplier: supplier, status: "received", ordered_at: 3.days.ago.to_date, total_amount: 150.0)

    sign_in user
    get suppliers_path
    assert_response :success

    supplier_json = inertia_props["suppliers"].find { |s| s["id"] == supplier.id }
    assert_equal 1, supplier_json["reference_count"]
    assert_equal 6, supplier_json["avg_lead_time_days"]
    assert_equal 10.0, supplier_json["stock_value"]
    assert_equal 1, supplier_json["order_count"]
    assert_equal "RES-10K", supplier_json["components"].first["reference"]
    assert_equal purchase.id, supplier_json["orders"].first["id"]
  end

  test "index does not leak another organization's suppliers" do
    user = create_user
    other_org = create_organization
    create_supplier(organization: other_org, name: "Someone else's supplier")

    sign_in user
    get suppliers_path
    assert_response :success

    names = inertia_props["suppliers"].map { |s| s["name"] }
    assert_not_includes names, "Someone else's supplier"
  end

  test "create builds a supplier" do
    user = create_user

    sign_in user
    assert_difference -> { Supplier.count } => 1 do
      post suppliers_path, params: { supplier: { name: "Digikey", email: "sales@digikey.com" } }
    end

    assert_redirected_to suppliers_path
    assert Supplier.exists?(name: "Digikey")
  end

  test "create fails with a blank name" do
    user = create_user

    sign_in user
    assert_no_difference "Supplier.count" do
      post suppliers_path, params: { supplier: { name: "" } }
    end

    assert_redirected_to suppliers_path
  end

  test "update edits a supplier" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org, name: "Old Name")

    sign_in user
    patch supplier_path(supplier), params: { supplier: { name: "New Name" } }

    assert_redirected_to suppliers_path
    assert_equal "New Name", supplier.reload.name
  end

  test "destroy removes a supplier" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org)

    sign_in user
    assert_difference -> { Supplier.count } => -1 do
      delete supplier_path(supplier)
    end

    assert_redirected_to suppliers_path
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

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
    order = Order.create!(organization: org, supplier: supplier, status: "received", ordered_at: 3.days.ago.to_date, total_amount: 150.0)

    sign_in user
    get suppliers_path
    assert_response :success

    supplier_json = inertia_props["suppliers"].find { |s| s["id"] == supplier.id }
    assert_equal 1, supplier_json["reference_count"]
    assert_equal 6, supplier_json["avg_lead_time_days"]
    assert_equal 10.0, supplier_json["stock_value"]
    assert_equal 1, supplier_json["order_count"]
    assert_equal order.ordered_at.iso8601, supplier_json["last_order_at"]
    assert_nil inertia_props["supplier_detail"], "a supplier's components and orders load with its sheet"
  end

  test "index sends one supplier's components and orders on request" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org, name: "Mouser")
    part = create_part(organization: org, mpn: "RES-10K")
    PartSupplier.create!(part: part, supplier: supplier, unit_price: 0.04)
    order = Order.create!(organization: org, supplier: supplier, status: "received", ordered_at: 3.days.ago.to_date, total_amount: 150.0)
    foreign = create_supplier(organization: create_organization, name: "Elsewhere")

    sign_in user
    get suppliers_path
    version = JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["version"].to_s
    headers = { "X-Inertia" => "true", "X-Inertia-Version" => version,
                "X-Inertia-Partial-Component" => "suppliers/index", "X-Inertia-Partial-Data" => "supplier_detail" }

    get suppliers_path(supplier: supplier.id), headers: headers
    detail = JSON.parse(@response.body)["props"]["supplier_detail"]
    assert_equal supplier.id, detail["id"]
    assert_equal "RES-10K", detail["components"].sole["reference"]
    assert_equal order.id, detail["orders"].sole["id"]

    get suppliers_path(supplier: foreign.id), headers: headers
    assert_nil JSON.parse(@response.body)["props"]["supplier_detail"]
  end

  test "index computes the figures without loading each supplier's parts" do
    user = create_user
    org = user.organizations.first
    suppliers = Array.new(3) { |i| create_supplier(organization: org, name: "Supplier #{i}") }
    suppliers.each { |supplier| 2.times { PartSupplier.create!(part: create_part(organization: org), supplier: supplier) } }

    sign_in user
    get suppliers_path
    queries = count_queries { get suppliers_path }
    suppliers << create_supplier(organization: org, name: "Supplier 4")
    PartSupplier.create!(part: create_part(organization: org), supplier: suppliers.last)
    assert_equal queries, count_queries { get suppliers_path }
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

  test "index serializes the catalog_provider tag" do
    user = create_user
    org = user.organizations.first
    sign_in user

    get suppliers_path
    providers = inertia_props["suppliers"].map { |s| s["catalog_provider"] }
    assert_includes providers, "mouser"
    assert_includes providers, "digikey"
    assert_includes providers, "lcsc"
  end

  test "destroy of a catalog supplier clears the provider's credentials" do
    user = create_user
    org = user.organizations.first
    org.update!(mouser_api_key: "secret-key", mouser_order_api_key: "order-key")
    mouser = org.suppliers.find_by(catalog_provider: "mouser")

    sign_in user
    delete supplier_path(mouser)

    assert_nil org.reload.mouser_api_key
    assert_nil org.mouser_order_api_key, "the Order/Cart API key belongs to the same integration"
    assert_match(/Mouser Electronics/, flash[:notice])
  end

  test "destroy of the LCSC supplier turns the LCSC lookup off" do
    user = create_user
    org = user.organizations.first
    org.update!(lcsc_enabled: true)

    sign_in user
    delete supplier_path(org.suppliers.find_by(catalog_provider: "lcsc"))

    refute org.reload.lcsc_enabled?
    assert_match(/LCSC catalog integration has been disabled/, flash[:notice])
  end

  test "a member can't delete a catalog supplier and wipe the integration" do
    owner = create_user
    org = owner.organizations.first
    org.update!(mouser_api_key: "secret-key")
    mouser = org.suppliers.find_by(catalog_provider: "mouser")
    member = create_user
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    post switch_organization_path(org)
    assert_no_difference -> { Supplier.count } do
      delete supplier_path(mouser)
    end

    assert_equal "secret-key", org.reload.mouser_api_key
    assert_match(/only an admin/i, flash[:alert])
  end

  test "a member can still delete a plain supplier" do
    owner = create_user
    org = owner.organizations.first
    supplier = create_supplier(organization: org)
    member = create_user
    OrganizationMembership.create!(organization: org, user: member, role: "member")

    sign_in member
    post switch_organization_path(org)
    assert_difference -> { Supplier.count } => -1 do
      delete supplier_path(supplier)
    end
  end

  test "destroy of the digikey supplier also drops the connected account tokens" do
    user = create_user
    org = user.organizations.first
    org.update!(digikey_client_id: "id", digikey_client_secret: "secret",
                digikey_access_token: "access", digikey_refresh_token: "refresh",
                digikey_token_expires_at: 1.hour.from_now)

    sign_in user
    delete supplier_path(org.suppliers.find_by(catalog_provider: "digikey"))

    org.reload
    assert_not org.digikey_configured?
    assert_not org.digikey_account_connected?
    assert_nil org.digikey_access_token
  end

  test "destroy of a plain supplier leaves credentials intact" do
    user = create_user
    org = user.organizations.first
    org.update!(mouser_api_key: "secret-key")
    supplier = create_supplier(organization: org)

    sign_in user
    delete supplier_path(supplier)

    assert_equal "secret-key", org.reload.mouser_api_key
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

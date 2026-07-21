require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  test "redirects a signed-out visitor to login" do
    get alerts_path
    assert_redirected_to new_user_session_path
  end

  test "index lists parts under threshold with severity and reorder quantity, excludes healthy parts" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org, name: "Resistors", color: "#F4A52B")
    location = create_storage_location(organization: org, name: "Shelf A")
    supplier = create_supplier(organization: org, name: "Mouser")

    critical = create_part(organization: org, category: category, mpn: "RES-CRIT", min_stock_threshold: 100, target_stock: 500, unit_price: 0.05)
    PartStorage.create!(part: critical, storage_location: location, quantity: 10)
    PartSupplier.create!(part: critical, supplier: supplier, is_preferred: true, unit_price: 0.02)

    low = create_part(organization: org, category: category, mpn: "RES-LOW", min_stock_threshold: 100, target_stock: 500)
    PartStorage.create!(part: low, storage_location: location, quantity: 80)

    healthy = create_part(organization: org, category: category, mpn: "RES-OK", min_stock_threshold: 10)
    PartStorage.create!(part: healthy, storage_location: location, quantity: 100)

    sign_in user
    get alerts_path
    assert_response :success

    refs = inertia_props["alerts"].map { |a| a["reference"] }
    assert_includes refs, "RES-CRIT"
    assert_includes refs, "RES-LOW"
    assert_not_includes refs, "RES-OK"

    critical_json = inertia_props["alerts"].find { |a| a["reference"] == "RES-CRIT" }
    assert_equal "critical", critical_json["severity"]
    assert_equal 490, critical_json["reorder_quantity"]
    assert_equal "Mouser", critical_json["supplier_name"]
    assert_equal 0.02, critical_json["unit_price"]

    low_json = inertia_props["alerts"].find { |a| a["reference"] == "RES-LOW" }
    assert_equal "low", low_json["severity"]
  end

  test "index does not leak another organization's alerts" do
    user = create_user
    other_org = create_organization
    other_category = create_category(organization: other_org)
    other_location = create_storage_location(organization: other_org)
    other_part = create_part(organization: other_org, category: other_category, min_stock_threshold: 100)
    PartStorage.create!(part: other_part, storage_location: other_location, quantity: 5)

    sign_in user
    get alerts_path
    assert_response :success
    assert_empty inertia_props["alerts"]
  end

  test "index includes pending and shipped orders but not received" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org, name: "Mouser")
    Order.create!(organization: org, supplier: supplier, status: "pending", reference: "PO-1")
    Order.create!(organization: org, supplier: supplier, status: "shipped", reference: "PO-2")
    Order.create!(organization: org, supplier: supplier, status: "received", reference: "PO-3")

    sign_in user
    get alerts_path
    assert_response :success

    refs = inertia_props["orders"].map { |o| o["reference"] }
    assert_includes refs, "PO-1"
    assert_includes refs, "PO-2"
    assert_not_includes refs, "PO-3"
  end

  test "create_purchase_orders groups alerts by preferred supplier and skips parts without one" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    supplier = create_supplier(organization: org, name: "Mouser")

    with_supplier = create_part(organization: org, category: category, min_stock_threshold: 50, target_stock: 200, unit_price: 0.01)
    PartStorage.create!(part: with_supplier, storage_location: location, quantity: 10)
    PartSupplier.create!(part: with_supplier, supplier: supplier, is_preferred: true, unit_price: 0.01)

    without_supplier = create_part(organization: org, category: category, min_stock_threshold: 50)
    PartStorage.create!(part: without_supplier, storage_location: location, quantity: 5)

    sign_in user
    assert_difference -> { Order.count } => 1, -> { OrderLine.count } => 1 do
      post alert_purchase_orders_path
    end

    order = Order.last
    assert_equal supplier, order.supplier
    assert_equal "pending", order.status
    assert_equal with_supplier, order.order_lines.first.part
  end

  test "create_purchase_orders scoped to a single part_id only orders that alert" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    supplier = create_supplier(organization: org)

    first = create_part(organization: org, category: category, min_stock_threshold: 50, target_stock: 200)
    PartStorage.create!(part: first, storage_location: location, quantity: 10)
    PartSupplier.create!(part: first, supplier: supplier, is_preferred: true, unit_price: 0.01)

    second = create_part(organization: org, category: category, min_stock_threshold: 50, target_stock: 200)
    PartStorage.create!(part: second, storage_location: location, quantity: 5)
    PartSupplier.create!(part: second, supplier: supplier, is_preferred: true, unit_price: 0.02)

    sign_in user
    assert_difference -> { OrderLine.count } => 1 do
      post alert_purchase_orders_path, params: { part_id: first.id }
    end

    assert_equal first, Order.last.order_lines.first.part
  end

  test "create_purchase_orders shows an alert when no eligible supplier exists" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org)
    part = create_part(organization: org, category: category, min_stock_threshold: 50)
    PartStorage.create!(part: part, storage_location: location, quantity: 5)

    sign_in user
    assert_no_difference "Order.count" do
      post alert_purchase_orders_path
    end

    assert_redirected_to alerts_path
    follow_redirect!
    assert_match(/preferred supplier/, flash[:alert])
  end

  test "advance_order moves pending to shipped without touching stock" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org)
    order = Order.create!(organization: org, supplier: supplier, status: "pending", reference: "PO-1")

    sign_in user
    assert_no_difference "StockMovement.count" do
      patch advance_alert_order_path(order)
    end

    assert_equal "shipped", order.reload.status
  end

  test "advance_order moving to received credits stock via a stock movement" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org, name: "Shelf A")
    supplier = create_supplier(organization: org)
    part = create_part(organization: org, category: category)
    PartStorage.create!(part: part, storage_location: location, quantity: 0)
    order = Order.create!(organization: org, supplier: supplier, status: "shipped", reference: "PO-1")
    OrderLine.create!(order: order, part: part, quantity: 40, unit_price: 0.02)

    sign_in user
    assert_difference -> { StockMovement.count } => 1 do
      patch advance_alert_order_path(order)
    end

    assert_equal "received", order.reload.status
    assert_equal 40, part.reload.total_quantity
  end

  test "advance_order to received warns and records no stock for a part with no location" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    supplier = create_supplier(organization: org)
    part = create_part(organization: org, category: category, mpn: "RES-NOLOC")
    order = Order.create!(organization: org, supplier: supplier, status: "shipped", reference: "PO-1")
    OrderLine.create!(order: order, part: part, quantity: 40, unit_price: 0.02)

    sign_in user
    assert_no_difference "StockMovement.count" do
      patch advance_alert_order_path(order)
    end

    assert_equal "received", order.reload.status
    assert_redirected_to alerts_path
    follow_redirect!
    assert_match(/RES-NOLOC/, flash[:alert])
    assert_match(/no storage location/, flash[:alert])
  end

  test "advance_order refuses to advance an already-received order" do
    user = create_user
    org = user.organizations.first
    supplier = create_supplier(organization: org)
    order = Order.create!(organization: org, supplier: supplier, status: "received", reference: "PO-1")

    sign_in user
    patch advance_alert_order_path(order)

    assert_redirected_to alerts_path
    follow_redirect!
    assert_match(/already been received/, flash[:alert])
  end

  test "advance_order does not credit stock a second time for an already-received order" do
    user = create_user
    org = user.organizations.first
    category = create_category(organization: org)
    location = create_storage_location(organization: org, name: "Shelf A")
    supplier = create_supplier(organization: org)
    part = create_part(organization: org, category: category)
    PartStorage.create!(part: part, storage_location: location, quantity: 0)
    order = Order.create!(organization: org, supplier: supplier, status: "shipped", reference: "PO-1")
    OrderLine.create!(order: order, part: part, quantity: 40, unit_price: 0.02)

    sign_in user
    patch advance_alert_order_path(order)
    assert_equal 40, part.reload.total_quantity

    # A repeat "advance" on the now-received order must not re-run receive_stock.
    assert_no_difference "StockMovement.count" do
      patch advance_alert_order_path(order)
    end
    assert_equal 40, part.reload.total_quantity
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json">(.*?)<\/script>/m, 1])["props"]
  end
end

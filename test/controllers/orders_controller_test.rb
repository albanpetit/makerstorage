require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @location = create_storage_location(organization: @org)
    @supplier = create_supplier(organization: @org)
    @part = create_part(organization: @org, category: @category, name: "Resistor 10k", mpn: "RC0805-10K")
    @part.part_storages.create!(storage_location: @location, quantity: 0)
  end

  test "redirects a signed-out visitor to login" do
    get orders_path
    assert_redirected_to new_user_session_path
  end

  test "index lists the organization's orders" do
    create_order(organization: @org, supplier: @supplier, reference: "PO-A", status: "pending")
    sign_in @user
    get orders_path
    assert_response :success
  end

  test "create builds a pending order with an auto-generated reference" do
    sign_in @user
    assert_difference -> { Order.count } => 1 do
      post orders_path, params: { order: { supplier_id: @supplier.id } }
    end

    order = Order.order(:created_at).last
    assert_redirected_to order_path(order)
    assert_equal "pending", order.status
    assert_equal @supplier, order.supplier
    assert_match(/\APO-/, order.reference)
    assert_equal Date.current, order.ordered_at
  end

  test "create without a supplier re-prompts" do
    sign_in @user
    assert_no_difference -> { Order.count } do
      post orders_path, params: { order: { supplier_id: "" } }
    end
    assert_redirected_to orders_path
    assert_match(/supplier/i, flash[:alert])
  end

  test "update changes metadata but refuses to receive via a plain status write" do
    order = create_order(organization: @org, supplier: @supplier, status: "pending", reference: "PO-1")
    sign_in @user

    patch order_path(order), params: { order: { notes: "rush" } }
    assert_equal "rush", order.reload.notes

    patch order_path(order), params: { order: { status: "received" } }
    assert_equal "pending", order.reload.status
    assert_match(/mark received/i, flash[:alert])
  end

  test "advance moves the order forward and credits stock on receipt" do
    order = create_order(organization: @org, supplier: @supplier, status: "shipped", reference: "PO-1")
    order.order_lines.create!(part: @part, quantity: 30, unit_price: 0.02)
    sign_in @user

    assert_difference -> { StockMovement.count } => 1 do
      patch advance_order_path(order)
    end
    assert_equal "received", order.reload.status
    assert_equal 30, @part.reload.total_quantity
  end

  test "import_project full pulls every matched BOM line into the order" do
    cap = create_part(organization: @org, category: @category, name: "Cap 100nF", sku: "CAP")
    project = create_project(organization: @org, reference: Project.next_reference(@org))
    project.project_lines.create!(part: @part, quantity: 5, match_type: "mpn")
    project.project_lines.create!(part: cap, quantity: 3, match_type: "sku")
    project.project_lines.create!(part: nil, quantity: 2, match_type: "none", raw_reference: "UNKNOWN")

    order = create_order(organization: @org, supplier: @supplier, status: "pending", reference: "PO-1")
    sign_in @user

    assert_difference -> { OrderLine.count } => 2 do
      post import_project_order_path(order), params: { project_id: project.id, mode: "full" }
    end
    assert_match(/imported 2 lines/i, flash[:notice])
    assert_match(/no matching part/i, flash[:alert])
    assert_equal 5, order.order_lines.find_by(part: @part).quantity
  end

  test "import_project shortfall orders only the uncovered quantity and tops up existing lines" do
    stock(@part, 2)
    project = create_project(organization: @org, reference: Project.next_reference(@org))
    project.project_lines.create!(part: @part, quantity: 5, match_type: "mpn")

    order = create_order(organization: @org, supplier: @supplier, status: "pending", reference: "PO-1")
    order.order_lines.create!(part: @part, quantity: 1, unit_price: 0.1)
    sign_in @user

    assert_no_difference -> { OrderLine.count } do
      post import_project_order_path(order), params: { project_id: project.id, mode: "shortfall" }
    end
    # shortfall = 5 required - 2 in stock = 3, added onto the existing quantity of 1.
    assert_equal 4, order.order_lines.find_by(part: @part).quantity
  end

  test "destroy removes the order" do
    order = create_order(organization: @org, supplier: @supplier, reference: "PO-1")
    sign_in @user
    assert_difference -> { Order.count } => -1 do
      delete order_path(order)
    end
    assert_redirected_to orders_path
  end

  test "does not expose another organization's order" do
    other = create_organization
    other_supplier = create_supplier(organization: other)
    foreign = create_order(organization: other, supplier: other_supplier, reference: "PO-X")
    sign_in @user
    get order_path(foreign)
    assert_response :not_found
  end

  test "viewers cannot create an order" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    assert_no_difference -> { Order.count } do
      post orders_path, params: { order: { supplier_id: @supplier.id } }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "push_to_cart builds a Mouser cart from lines with a Mouser SKU" do
    mouser, = Supplier.ensure_catalog_provider(@org, "mouser")
    @part.part_suppliers.create!(supplier: mouser, supplier_sku: "603-RC0805")
    order = create_order(organization: @org, supplier: mouser, status: "pending", reference: "PO-1")
    order.order_lines.create!(part: @part, quantity: 3)
    @org.update!(mouser_order_api_key: "order-key")
    sign_in @user

    cart = SupplierCatalog::CartResult.new(cart_key: "abc", merchandise_total: "1.50", currency: "EUR", lines: [])
    fake = FakeOrderClient.new(cart: cart)
    stub_singleton(SupplierCatalog, :mouser_order_client, ->(_org) { fake }) do
      post push_to_cart_order_path(order)
    end
    assert_match(/built a mouser cart/i, flash[:notice])
  end

  test "push_to_cart without the order key prompts to configure it" do
    mouser, = Supplier.ensure_catalog_provider(@org, "mouser")
    order = create_order(organization: @org, supplier: mouser, status: "pending", reference: "PO-1")
    sign_in @user
    post push_to_cart_order_path(order)
    assert_match(/order api key/i, flash[:alert])
  end

  test "import_supplier_order creates an order and reconciles new parts" do
    @org.update!(mouser_order_api_key: "order-key")
    sign_in @user

    result = SupplierCatalog::OrderResult.new(
      order_number: "9988", status: "Shipped", placed_at: "2026-07-01", total: "5.0", currency: "EUR",
      lines: [
        SupplierCatalog::OrderLineResult.new(
          mpn: "NEW-IC-1", manufacturer: "ACME", supplier_sku: "603-new",
          description: "New op-amp", quantity: 10, unit_price: "0.50"
        )
      ]
    )
    fake = FakeOrderClient.new(order: result)

    assert_difference -> { Order.count } => 1, -> { Part.count } => 1 do
      stub_singleton(SupplierCatalog, :mouser_order_client, ->(_org) { fake }) do
        post import_supplier_order_orders_path, params: { order_number: "9988" }
      end
    end

    order = Order.order(:created_at).last
    assert_equal "9988", order.reference
    assert_equal 10, order.order_lines.first.quantity
    assert_redirected_to order_path(order)
  end

  test "import_supplier_order refuses a duplicate reference" do
    @org.update!(mouser_order_api_key: "order-key")
    mouser, = Supplier.ensure_catalog_provider(@org, "mouser")
    create_order(organization: @org, supplier: mouser, reference: "9988")
    sign_in @user

    result = SupplierCatalog::OrderResult.new(order_number: "9988", lines: [
      SupplierCatalog::OrderLineResult.new(mpn: "X", quantity: 1)
    ])
    fake = FakeOrderClient.new(order: result)

    assert_no_difference -> { Order.count } do
      stub_singleton(SupplierCatalog, :mouser_order_client, ->(_org) { fake }) do
        post import_supplier_order_orders_path, params: { order_number: "9988" }
      end
    end
    assert_match(/already been imported/i, flash[:alert])
  end

  test "import_supplier_order via digikey imports and reconciles a new part" do
    @org.update!(
      digikey_client_id: "cid", digikey_client_secret: "csecret",
      digikey_access_token: "acc", digikey_refresh_token: "ref", digikey_token_expires_at: 1.hour.from_now
    )
    sign_in @user

    result = SupplierCatalog::OrderResult.new(
      order_number: "DK-77", status: "Shipped", placed_at: "2026-07-01", lines: [
        SupplierCatalog::OrderLineResult.new(
          mpn: "DK-NEW", manufacturer: "Microchip", supplier_sku: "DK-NEW-ND",
          description: "MCU", quantity: 5, unit_price: "1.00"
        )
      ]
    )
    fake = FakeOrderClient.new(order: result)

    assert_difference -> { Order.count } => 1, -> { Part.count } => 1 do
      stub_singleton(SupplierCatalog, :digikey_order_client, ->(_org) { fake }) do
        post import_supplier_order_orders_path, params: { provider: "digikey", order_number: "DK-77" }
      end
    end

    order = Order.order(:created_at).last
    assert_equal "DK-77", order.reference
    assert_match(/DigiKey/, order.notes.to_s)
  end

  test "import_supplier_order via digikey prompts to connect when no account" do
    sign_in @user
    post import_supplier_order_orders_path, params: { provider: "digikey", order_number: "DK-1" }
    assert_match(/connect your digikey account/i, flash[:alert])
  end

  test "assign_storage presets one full-quantity allocation per line" do
    order = create_order(organization: @org, supplier: @supplier, status: "pending", reference: "PO-2")
    cap = create_part(organization: @org, category: @category, name: "Cap 100nF")
    order.order_lines.create!(part: @part, quantity: 5)
    order.order_lines.create!(part: cap, quantity: 3)
    zone = create_storage_location(organization: @org, name: "Shelf X")
    sign_in @user

    post assign_storage_order_path(order), params: { storage_location_id: zone.id }

    order.order_lines.each do |line|
      assert_equal 1, line.allocations.count
      assert_equal line.quantity, line.allocations.first.quantity
      assert_equal zone, line.allocations.first.storage_location
    end
  end

  test "advancing a bulk-assigned order credits stock into the chosen zone" do
    order = create_order(organization: @org, supplier: @supplier, status: "shipped", reference: "PO-3")
    order.order_lines.create!(part: @part, quantity: 5)
    zone = create_storage_location(organization: @org, name: "Shelf Y")
    sign_in @user

    post assign_storage_order_path(order), params: { storage_location_id: zone.id }
    patch advance_order_path(order)

    assert_equal "received", order.reload.status
    assert_equal 5, PartStorage.find_by(part: @part, storage_location: zone).quantity
  end

  private

  # Stands in for a configured SupplierCatalog::Mouser order client.
  class FakeOrderClient
    def initialize(cart: nil, order: nil)
      @cart = cart
      @order = order
    end

    def create_cart(_items, currency: nil)
      @cart
    end

    def import_order(_number)
      @order
    end
  end

  def stock(part, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: @location,
      movement_type: "in", quantity_delta: quantity)
  end
end

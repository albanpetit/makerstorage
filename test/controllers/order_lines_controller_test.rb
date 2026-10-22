require "test_helper"

class OrderLinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @supplier = create_supplier(organization: @org)
    @part = create_part(organization: @org, category: @category, name: "Cap 100nF", unit_price: 0.05)
    @order = create_order(organization: @org, supplier: @supplier, status: "pending", reference: "PO-1")
  end

  test "create adds a line and recomputes the order total" do
    sign_in @user
    assert_difference -> { OrderLine.count } => 1 do
      post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 10 } }
    end

    line = @order.order_lines.last
    assert_equal 10, line.quantity
    # Price falls back to the part's cost basis when none is given.
    assert_equal 0.05, line.unit_price.to_f
    assert_equal 0.5, @order.reload.total_amount.to_f
  end

  test "create honours an explicit unit price" do
    sign_in @user
    post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 4, unit_price: 1.25 } }
    assert_equal 1.25, @order.order_lines.last.unit_price.to_f
  end

  test "create tops up the line of a part already on the order" do
    line = @order.order_lines.create!(part: @part, quantity: 3, unit_price: 2.0)
    sign_in @user

    assert_no_difference -> { OrderLine.count } do
      post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 4 } }
    end

    assert_equal 7, line.reload.quantity
    assert_equal 2.0, line.unit_price.to_f, "an existing line keeps its price unless one is given"
    assert_equal 14.0, @order.reload.total_amount.to_f
  end

  test "create refuses a quantity that isn't a positive whole number" do
    line = @order.order_lines.create!(part: @part, quantity: 3)
    sign_in @user

    post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: "1.5" } }

    assert_equal 3, line.reload.quantity
    assert_match(/quantity/i, flash[:alert])
  end

  test "update reprices a line and recomputes the total" do
    line = @order.order_lines.create!(part: @part, quantity: 2, unit_price: 1.0)
    sign_in @user

    patch order_order_line_path(@order, line), params: { order_line: { quantity: 5, unit_price: 2.0 } }
    assert_equal 5, line.reload.quantity
    assert_equal 10.0, @order.reload.total_amount.to_f
  end

  test "destroy removes a line and recomputes the total" do
    line = @order.order_lines.create!(part: @part, quantity: 2, unit_price: 1.0)
    @order.recalculate_total!
    sign_in @user

    assert_difference -> { OrderLine.count } => -1 do
      delete order_order_line_path(@order, line)
    end
    assert_equal 0.0, @order.reload.total_amount.to_f
  end

  test "cannot edit lines of a received order" do
    received = create_order(organization: @org, supplier: @supplier, status: "received", reference: "PO-R")
    sign_in @user
    assert_no_difference -> { OrderLine.count } do
      post order_order_lines_path(received), params: { order_line: { part_id: @part.id, quantity: 1 } }
    end
    assert_match(/received/i, flash[:alert])
  end

  test "catalog creates a new part, links the order supplier, and adds a line" do
    sign_in @user
    assert_difference -> { Part.count } => 1, -> { OrderLine.count } => 1 do
      post catalog_order_order_lines_path(@order), params: {
        category_id: @category.id,
        order_line: { quantity: 8 },
        supplier_sku: "MO-123",
        part: { name: "LM358 op-amp", mpn: "LM358DR", unit_price: "0.42" }
      }
    end

    part = Part.order(:created_at).last
    assert_equal "LM358DR", part.mpn
    assert_equal @category, part.category
    line = @order.order_lines.last
    assert_equal part, line.part
    assert_equal 8, line.quantity
    assert_equal 0.42, line.unit_price.to_f
    # Linked to this order's supplier for reordering.
    assert part.part_suppliers.exists?(supplier: @supplier)
  end

  test "catalog keeps a supplier image and drops one from any other host" do
    sign_in @user
    post catalog_order_order_lines_path(@order), params: {
      category_id: @category.id, order_line: { quantity: 1 },
      part: { name: "From Mouser", mpn: "MPN-MOUSER" }, image_url: "http://www.mouser.com/images/a.jpg"
    }
    post catalog_order_order_lines_path(@order), params: {
      category_id: @category.id, order_line: { quantity: 1 },
      part: { name: "From elsewhere", mpn: "MPN-OTHER" }, image_url: "https://tracker.example/pixel.png"
    }

    assert_equal "https://www.mouser.com/images/a.jpg", Part.find_by!(mpn: "MPN-MOUSER").image_source_url
    assert_nil Part.find_by!(mpn: "MPN-OTHER").image_source_url
  end

  test "catalog leaves no new part behind when the line is rejected" do
    sign_in @user
    assert_no_difference [ "Part.count", "PartSupplier.count", "OrderLine.count" ] do
      post catalog_order_order_lines_path(@order), params: {
        category_id: @category.id,
        order_line: { quantity: 0 },
        part: { name: "LM358 op-amp", mpn: "LM358DR" }
      }
    end

    assert_redirected_to order_path(@order)
    assert_match(/quantity/i, flash[:alert])
  end

  test "catalog reports a component it couldn't create" do
    sign_in @user
    assert_no_difference [ "Part.count", "OrderLine.count" ] do
      post catalog_order_order_lines_path(@order), params: {
        category_id: @category.id, order_line: { quantity: 1 }, part: { name: "" }
      }
    end

    assert_match(/name/i, flash[:alert])
  end

  test "catalog reuses an existing part with the same MPN instead of duplicating" do
    existing = create_part(organization: @org, category: @category, name: "Existing", mpn: "REUSE-1")
    sign_in @user

    assert_no_difference -> { Part.count } do
      assert_difference -> { OrderLine.count } => 1 do
        post catalog_order_order_lines_path(@order), params: {
          category_id: @category.id,
          order_line: { quantity: 2 },
          part: { name: "Whatever", mpn: "reuse-1" }
        }
      end
    end
    assert_equal existing, @order.order_lines.last.part
  end

  test "catalog tops up the line when the reused part is already on the order" do
    existing = create_part(organization: @org, category: @category, name: "Existing", mpn: "REUSE-2")
    line = @order.order_lines.create!(part: existing, quantity: 5, unit_price: 0.3)
    sign_in @user

    assert_no_difference -> { OrderLine.count } do
      post catalog_order_order_lines_path(@order), params: {
        category_id: @category.id, order_line: { quantity: 2 }, part: { name: "Whatever", mpn: "REUSE-2", unit_price: "0.9" }
      }
    end

    assert_equal 7, line.reload.quantity
    assert_equal 0.3, line.unit_price.to_f
  end

  test "catalog without a category re-prompts" do
    sign_in @user
    assert_no_difference -> { Part.count } do
      post catalog_order_order_lines_path(@order), params: {
        order_line: { quantity: 1 },
        part: { name: "No category", mpn: "NC-1" }
      }
    end
    assert_match(/category/i, flash[:alert])
  end

  test "viewers cannot add lines" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    assert_no_difference -> { OrderLine.count } do
      post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 1 } }
    end
    assert_match(/read-only/i, flash[:alert])
  end

  test "update stores a balanced storage split" do
    line = @order.order_lines.create!(part: @part, quantity: 10)
    a = create_storage_location(organization: @org)
    b = create_storage_location(organization: @org)
    sign_in @user

    patch order_order_line_path(@order, line), params: {
      order_line: { allocations: [ { storage_location_id: a.id, quantity: 7 }, { storage_location_id: b.id, quantity: 3 } ] }
    }

    assert_equal 2, line.reload.allocations.count
    assert line.fully_allocated?
  end

  test "update reads a storage split sent as an index-keyed hash" do
    line = @order.order_lines.create!(part: @part, quantity: 10)
    a = create_storage_location(organization: @org)
    b = create_storage_location(organization: @org)
    sign_in @user

    patch order_order_line_path(@order, line), params: {
      order_line: { allocations: { "0" => { storage_location_id: a.id, quantity: 6 }, "1" => { storage_location_id: b.id, quantity: 4 } } }
    }

    assert_equal [ 6, 4 ], line.reload.allocations.order(:id).pluck(:quantity)
  end

  test "update ignores malformed storage split rows instead of failing" do
    line = @order.order_lines.create!(part: @part, quantity: 10)
    a = create_storage_location(organization: @org)
    line.allocations.create!(storage_location: a, quantity: 10)
    sign_in @user

    patch order_order_line_path(@order, line), params: { order_line: { allocations: [ "junk" ] } }

    assert_redirected_to order_path(@order)
    assert_empty line.reload.allocations
  end

  test "update rejects an unbalanced storage split" do
    line = @order.order_lines.create!(part: @part, quantity: 10)
    a = create_storage_location(organization: @org)
    sign_in @user

    assert_no_difference -> { OrderLineAllocation.count } do
      patch order_order_line_path(@order, line), params: {
        order_line: { allocations: [ { storage_location_id: a.id, quantity: 4 } ] }
      }
    end
    assert_match(/add up to the line quantity/i, flash[:alert])
  end

  test "changing the quantity clears a stale split" do
    line = @order.order_lines.create!(part: @part, quantity: 10)
    location = create_storage_location(organization: @org)
    line.allocations.create!(storage_location: location, quantity: 10)
    sign_in @user

    patch order_order_line_path(@order, line), params: { order_line: { quantity: 8 } }

    assert_equal 8, line.reload.quantity
    assert_empty line.allocations
  end

  test "create with a blank price uses the supplier's price break for the quantity" do
    @part.part_suppliers.create!(supplier: @supplier, unit_price: 0.1, price_breaks: [ { quantity: 100, unit_price: "0.04" } ])
    sign_in @user

    post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 250, unit_price: "" } }

    assert_equal 0.04, @order.order_lines.last.unit_price.to_f
    assert_equal 10.0, @order.reload.total_amount.to_f
  end

  test "topping a line up past a break moves it to the break's price" do
    @part.part_suppliers.create!(supplier: @supplier, unit_price: 0.1, price_breaks: [ { quantity: 100, unit_price: "0.04" } ])
    line = @order.order_lines.create!(part: @part, quantity: 60, unit_price: 0.1)
    sign_in @user

    post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 50 } }

    assert_equal 110, line.reload.quantity
    assert_equal 0.04, line.unit_price.to_f
  end

  test "changing the quantity follows the price breaks, a typed price stays" do
    @part.part_suppliers.create!(supplier: @supplier, unit_price: 0.1, price_breaks: [ { quantity: 100, unit_price: "0.04" } ])
    line = @order.order_lines.create!(part: @part, quantity: 10, unit_price: 0.1)
    typed = @order.order_lines.create!(part: create_part(organization: @org, category: @category), quantity: 10, unit_price: 0.5)
    sign_in @user

    patch order_order_line_path(@order, line), params: { order_line: { quantity: 100 } }
    assert_equal 0.04, line.reload.unit_price.to_f

    patch order_order_line_path(@order, line), params: { order_line: { quantity: 20 } }
    assert_equal 0.1, line.reload.unit_price.to_f

    patch order_order_line_path(@order, typed), params: { order_line: { quantity: 200 } }
    assert_equal 0.5, typed.reload.unit_price.to_f

    patch order_order_line_path(@order, line), params: { order_line: { quantity: 500, unit_price: 0.07 } }
    assert_equal 0.07, line.reload.unit_price.to_f, "a price sent with the quantity wins"
  end

  test "catalog keeps the result's price breaks on the supplier link and prices the line with them" do
    sign_in @user
    post catalog_order_order_lines_path(@order), params: {
      category_id: @category.id,
      order_line: { quantity: 100 },
      supplier_sku: "MO-555",
      price_breaks: [ { quantity: 1, unit_price: "0.42" }, { quantity: 100, unit_price: "0.0215" } ],
      part: { name: "LM358 op-amp", mpn: "LM358-BRK", unit_price: "0.42" }
    }

    part = Part.find_by!(mpn: "LM358-BRK")
    link = part.part_suppliers.find_by!(supplier: @supplier)
    assert_equal [ 1, 100 ], link.price_breaks.map { |row| row["quantity"] }
    assert_equal BigDecimal("0.0215"), @order.order_lines.find_by!(part: part).unit_price
  end
end

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
    @order.update!(status: "received")
    sign_in @user
    assert_no_difference -> { OrderLine.count } do
      post order_order_lines_path(@order), params: { order_line: { part_id: @part.id, quantity: 1 } }
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
end

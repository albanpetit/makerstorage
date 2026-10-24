require "test_helper"

class DashboardSummaryTest < ActiveSupport::TestCase
  setup do
    @org = create_organization(timezone: "Europe/Paris")
    @category = create_category(organization: @org, name: "Resistors")
    @location = create_storage_location(organization: @org, name: "Shelf A")
    @now = Time.zone.parse("2026-10-21 10:00 UTC")
  end

  def summary
    DashboardSummary.new(@org, now: @now)
  end

  def stock(part, quantity, type: "in", at: @now)
    StockMovement.create!(organization: @org, part: part, storage_location: @location, movement_type: type,
                          quantity_delta: quantity, created_at: at)
  end

  test "stats count references, new ones, open and late orders" do
    old = create_part(organization: @org, category: @category, min_stock_threshold: 10, created_at: @now - 60.days)
    create_part(organization: @org, category: @category, min_stock_threshold: 10)
    stock(old, 3)
    order = create_order(organization: @org, status: "pending", expected_delivery: Date.new(2026, 10, 20))
    OrderLine.create!(order: order, part: old, quantity: 4, unit_price: 2.5)
    create_order(organization: @org, status: "shipped", expected_delivery: Date.new(2026, 10, 25))
    create_order(organization: @org, status: "cancelled", expected_delivery: Date.new(2026, 10, 1))

    stats = summary.stats
    assert_equal 2, stats[:references_count]
    assert_equal 1, stats[:new_references_count]
    assert_equal 2, stats[:alerts_count]
    assert_equal 1, stats[:out_of_stock_count]
    assert_equal 2, stats[:open_orders_count]
    assert_equal 1, stats[:late_orders_count]
    assert_in_delta 10.0, stats[:incoming_value]
  end

  test "activity has one entry per local day, counting movements by type" do
    part = create_part(organization: @org, category: @category)
    stock(part, 10, at: @now)
    stock(part, -2, type: "out", at: @now)
    # 23:30 UTC on the 19th is already the 20th in Paris.
    stock(part, 5, at: Time.zone.parse("2026-10-19 23:30 UTC"))
    stock(part, 1, type: "adjustment", at: @now - 40.days)

    activity = summary.activity
    assert_equal DashboardSummary::ACTIVITY_DAYS, activity.size
    assert_equal "2026-10-21", activity.last[:date]
    assert_equal({ date: "2026-10-21", in: 1, out: 1, adjustment: 0 }, activity.last)
    assert_equal 1, activity[-2][:in]
    assert_equal 0, activity.sum { |day| day[:adjustment] }
  end

  test "attention lists only what applies" do
    assert_empty summary.attention

    low = create_part(organization: @org, category: @category, min_stock_threshold: 10)
    stock(low, 2)
    create_part(organization: @org, category: @category, min_stock_threshold: 1)
    create_order(organization: @org, status: "shipped", expected_delivery: Date.new(2026, 10, 10))
    project = create_project(organization: @org, status: "confirmed")
    ProjectLine.create!(project: project, part: low, quantity: 5)

    kinds = summary.attention.to_h { |item| [ item[:kind], item[:count] ] }
    assert_equal({ "late_orders" => 1, "shipped_orders" => 1, "out_of_stock" => 1, "low_stock" => 1, "projects_short" => 1 }, kinds)
  end

  test "low stock parts carry what is already on open orders" do
    part = create_part(organization: @org, category: @category, min_stock_threshold: 10)
    stock(part, 2)
    order = create_order(organization: @org, status: "pending")
    OrderLine.create!(order: order, part: part, quantity: 20)

    row = summary.low_stock_parts.first
    assert_equal part.id, row[:id]
    assert_equal 2, row[:quantity]
    assert_equal 20, row[:incoming]
    assert_equal "Shelf A", row[:location_name]
  end

  test "open orders put late ones first and leave out closed ones" do
    later = create_order(organization: @org, status: "pending", expected_delivery: Date.new(2026, 11, 2))
    late = create_order(organization: @org, status: "shipped", expected_delivery: Date.new(2026, 10, 18))
    undated = create_order(organization: @org, status: "pending")
    create_order(organization: @org, status: "cancelled")

    orders = summary.open_orders
    assert_equal [ late.id, later.id, undated.id ], orders.map { |order| order[:id] }
    assert_equal 3, orders.first[:days_late]
    assert_equal 0, orders.second[:days_late]
  end

  test "projects say whether they can be built from stock" do
    part = create_part(organization: @org, category: @category)
    stock(part, 4)
    ok = create_project(organization: @org, status: "confirmed")
    ProjectLine.create!(project: ok, part: part, quantity: 2)
    short = create_project(organization: @org)
    ProjectLine.create!(project: short, part: part, quantity: 9)
    ProjectLine.create!(project: short, raw_reference: "U1", quantity: 1)

    projects = summary.projects.index_by { |project| project[:id] }
    assert projects[ok.id][:buildable]
    assert_not projects[short.id][:buildable]
    assert_equal 2, projects[short.id][:short_count]
  end

  test "top consumed ranks parts by units taken out over the window" do
    small = create_part(organization: @org, category: @category, mpn: "SMALL")
    big = create_part(organization: @org, category: @category, mpn: "BIG")
    stock(small, 100)
    stock(big, 100)
    stock(small, -3, type: "out")
    stock(big, -40, type: "out")
    stock(small, -50, type: "out", at: @now - 45.days)

    assert_equal [ [ "BIG", 40 ], [ "SMALL", 3 ] ], summary.top_consumed.map { |row| [ row[:reference], row[:units] ] }
  end

  test "category breakdown folds small categories into Other" do
    (DashboardSummary::CATEGORIES_LIMIT + 2).times do |index|
      category = create_category(organization: @org, name: "Cat #{index}")
      (index + 1).times { create_part(organization: @org, category: category) }
    end

    breakdown = summary.category_breakdown
    assert_equal DashboardSummary::CATEGORIES_LIMIT + 1, breakdown.size
    assert_equal "Cat 7", breakdown.first[:name]
    assert_equal({ name: "Other", count: 3, pct: 8 }, breakdown.last)
  end

  test "first steps tick themselves from the organization's data" do
    steps = summary.getting_started[:steps].to_h { |step| [ step[:key], step[:done] ] }
    assert steps["zones"]
    assert steps["categories"]
    assert_not steps["part"]
    assert_not steps["stock"]
    assert_not steps["members"]
    assert_not summary.getting_started[:choose_template], "the org already has categories and zones"

    stock(create_part(organization: @org, category: @category), 1)
    steps = summary.getting_started[:steps].to_h { |step| [ step[:key], step[:done] ] }
    assert steps["part"]
    assert steps["stock"]
  end

  test "first steps are put away for good once all done" do
    stock(create_part(organization: @org, category: @category), 1)
    create_supplier(organization: @org)
    create_project(organization: @org)
    @org.organization_memberships.create!(user: create_user, role: "owner")
    @org.organization_memberships.create!(user: create_user, role: "member")

    assert_nil summary.getting_started
    assert @org.reload.onboarding_dismissed_at
    @org.projects.destroy_all
    assert_nil summary.getting_started
  end

  test "first steps hide when dismissed and in a demo" do
    @org.update_columns(onboarding_dismissed_at: Time.current)
    assert_nil summary.getting_started

    @org.update_columns(onboarding_dismissed_at: nil, demo: true)
    assert_nil summary.getting_started
  end

  test "never reads another organization's data" do
    other = create_organization
    other_part = create_part(organization: other, category: create_category(organization: other), min_stock_threshold: 5)
    StockMovement.create!(organization: other, part: other_part, movement_type: "in", quantity_delta: 1,
                          storage_location: create_storage_location(organization: other))
    create_order(organization: other, status: "pending", expected_delivery: Date.new(2026, 1, 1))
    create_project(organization: other)

    props = summary.as_props
    assert_equal 0, props[:stats][:references_count]
    assert_equal 0, props[:stats][:open_orders_count]
    assert_empty props[:attention]
    assert_empty props[:projects]
    assert_empty props[:recent_movements]
    assert_equal 0, props[:activity].sum { |day| day[:in] }
  end
end

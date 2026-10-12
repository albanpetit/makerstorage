require "test_helper"

class PartsIndexQueryTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @resistors = create_category(organization: @org, name: "Resistors")
    @caps = create_category(organization: @org, name: "Capacitors")
    @shelf = create_storage_location(organization: @org, name: "Shelf A")
    @mouser = create_supplier(organization: @org, name: "Mouser")
  end

  def query(**params)
    PartsIndexQuery.new(@org, ActionController::Parameters.new(params))
  end

  def stock(part, quantity)
    PartStorage.create!(part: part, storage_location: @shelf, quantity: quantity)
  end

  test "searches names, references, category and location names case-insensitively" do
    by_mpn = create_part(organization: @org, category: @resistors, name: "Thing", mpn: "RC0603-10K")
    by_location = create_part(organization: @org, category: @caps, name: "Other")
    stock(by_location, 3)
    create_part(organization: @org, category: @caps, name: "Unrelated")

    assert_equal [ by_mpn.id ], query(search: "rc0603").matching_ids
    assert_equal [ by_location.id ], query(search: "shelf a").matching_ids
    assert_equal [ by_mpn.id ], query(search: "RESISTORS").matching_ids
  end

  test "filters by category, stock status, package, footprint and preferred supplier" do
    footprint = create_footprint(organization: @org, name: "SOT-23")
    out = create_part(organization: @org, category: @resistors, name: "Out", min_stock_threshold: 5)
    low = create_part(organization: @org, category: @resistors, name: "Low", min_stock_threshold: 5, package_type: "0603")
    ok = create_part(organization: @org, category: @caps, name: "Ok", min_stock_threshold: 5, footprint: footprint)
    stock(low, 2)
    stock(ok, 10)
    PartSupplier.create!(part: ok, supplier: @mouser, is_preferred: true)

    assert_equal [ low.id, out.id ], query(category: @resistors.id.to_s).matching_ids
    assert_equal [ out.id ], query(status: [ "out" ]).matching_ids
    assert_equal [ low.id, ok.id ].sort, query(status: [ "low", "ok" ]).matching_ids.sort
    assert_equal [ low.id ], query(package: [ "0603" ]).matching_ids
    assert_equal [ ok.id ], query(footprint: [ "SOT-23" ]).matching_ids
    assert_equal [ ok.id ], query(supplier: [ "Mouser" ]).matching_ids
  end

  test "facet counts follow search and category, category chips count every part" do
    a = create_part(organization: @org, category: @resistors, name: "Aa", package_type: "0603", min_stock_threshold: 1)
    create_part(organization: @org, category: @resistors, name: "Bb", package_type: "0805")
    create_part(organization: @org, category: @caps, name: "Cc", package_type: "0603")
    stock(a, 1)

    facets = query(category: @resistors.id.to_s).facets

    assert_equal [ { value: "0603", label: "0603", count: 1 }, { value: "0805", label: "0805", count: 1 } ], facets[:package]
    assert_equal [ "Capacitors", "Resistors" ], facets[:categories].map { |chip| chip[:name] }
    assert_equal [ 1, 2 ], facets[:categories].map { |chip| chip[:count] }
    assert_equal({ "out" => 1, "ok" => 1 }, facets[:status].to_h { |s| [ s[:value], s[:count] ] })
  end

  test "sorts by reference, then by the requested key" do
    zed = create_part(organization: @org, category: @resistors, name: "Zed", min_stock_threshold: 1)
    alpha = create_part(organization: @org, category: @resistors, name: "Alpha", min_stock_threshold: 10)
    stock(zed, 50)
    stock(alpha, 5)

    assert_equal [ alpha.id, zed.id ], query.matching_ids
    assert_equal [ zed.id, alpha.id ], query(sort: "qtyDesc").matching_ids
    assert_equal [ alpha.id, zed.id ], query(sort: "crit").matching_ids
    assert_equal [ alpha.id, zed.id ], query(sort: "nonsense").matching_ids
  end

  test "paginates the matching parts and clamps the page" do
    ids = Array.new(PartsIndexQuery::PAGE_SIZE + 3) { |i| create_part(organization: @org, category: @resistors, name: format("P%03d", i)).id }

    first = query
    assert_equal ids.first(PartsIndexQuery::PAGE_SIZE), first.page_ids
    assert_equal({ page: 1, page_count: 2, page_size: PartsIndexQuery::PAGE_SIZE, total: ids.size }, first.pagination)
    assert_equal ids.last(3), query(page: "2").page_ids
    assert_equal 2, query(page: "99").page
    assert_equal 1, query(page: "-4").page
  end

  test "only ever sees the organization's own parts" do
    other = create_organization
    create_part(organization: other, name: "Foreign")
    mine = create_part(organization: @org, category: @resistors, name: "Mine")

    assert_equal [ mine.id ], query.matching_ids
    assert_empty query(search: "foreign").matching_ids
  end
end

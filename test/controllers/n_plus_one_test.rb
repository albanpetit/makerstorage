require "test_helper"

# Pins the A1–A4 N+1 fixes shut. Each test issues the same request against a
# small dataset and a larger one and asserts the query count doesn't grow with
# the number of rows — the defining signature of an N+1 regression. If someone
# reverts a preload or re-introduces a per-row `total_quantity` query, the count
# scales with the data and the assertion fails.
class NPlusOneTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @location = create_storage_location(organization: @org)
    @supplier = create_supplier(organization: @org)
    sign_in @user
  end

  # Adds a low-stock part (quantity below threshold) with a stored quantity and a
  # preferred supplier link, so it surfaces in every list under test.
  def add_low_stock_part
    part = create_part(organization: @org, category: @category, min_stock_threshold: 100, target_stock: 500, unit_price: 0.5)
    PartStorage.create!(part: part, storage_location: @location, quantity: 10)
    PartSupplier.create!(part: part, supplier: @supplier, is_preferred: true, unit_price: 0.25)
    part
  end

  # Measures the request against a small dataset, then adds many more rows and
  # measures again. A fixed-query (preloaded) implementation stays flat bar a
  # tiny constant of request-level noise; a per-row N+1 grows by roughly the
  # number of rows added, so a large delta gives clear separation from noise.
  ROWS_ADDED = 20
  QUERY_NOISE_TOLERANCE = 3

  def assert_no_query_growth(path)
    2.times { add_low_stock_part }
    baseline = count_queries { get path }
    assert_response :success

    ROWS_ADDED.times { add_low_stock_part }
    grown = count_queries { get path }
    assert_response :success

    growth = grown - baseline
    assert growth <= QUERY_NOISE_TOLERANCE,
      "#{path} query count grew by #{growth} (#{baseline} → #{grown}) after adding #{ROWS_ADDED} rows — an N+1 has been reintroduced."
  end

  test "parts index does not N+1 on stock/supplier per part (A2/A4 root cause)" do
    assert_no_query_growth parts_path
  end

  test "suppliers index does not N+1 summing part stock per linked part (A1)" do
    assert_no_query_growth suppliers_path
  end

  test "dashboard low-stock list does not N+1 on stock per part (A2)" do
    assert_no_query_growth root_path
  end

  test "alerts index does not N+1 on stock/supplier per low-stock part" do
    assert_no_query_growth alerts_path
  end
end

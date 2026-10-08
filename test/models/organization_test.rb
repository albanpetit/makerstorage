require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "valid with just a name" do
    org = Organization.new(name: "Acme")
    assert org.valid?
  end

  test "invalid without a name" do
    org = Organization.new
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "defaults ipn settings" do
    org = create_organization
    assert_equal "MS", org.ipn_prefix
    assert_equal true, org.ipn_use_category_code
    assert_equal "-", org.ipn_separator
    assert_equal 5, org.ipn_digits
    assert_equal 1, org.ipn_next_sequence
    assert_equal "EUR", org.currency
    assert_equal false, org.allow_negative_stock
  end

  test "rejects an ipn_separator outside the allowed set" do
    org = create_organization
    org.ipn_separator = "*"
    assert_not org.valid?
    assert_includes org.errors[:ipn_separator], "is not included in the list"
  end

  test "rejects ipn_digits outside 3..8" do
    org = create_organization
    org.ipn_digits = 2
    assert_not org.valid?

    org.ipn_digits = 9
    assert_not org.valid?
  end

  test "next_ipn builds prefix, sequence, and padding" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 42)
    assert_equal "MS-00042", org.next_ipn
  end

  test "next_ipn includes the category code when enabled and given" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: true, ipn_separator: "-", ipn_digits: 4, ipn_next_sequence: 7)
    assert_equal "MS-RES-0007", org.next_ipn(category_code: "RES")
  end

  test "next_ipn omits the category code when disabled even if given" do
    org = create_organization(ipn_use_category_code: false, ipn_next_sequence: 1)
    assert_no_match(/RES/, org.next_ipn(category_code: "RES"))
  end

  test "next_ipn accepts an explicit sequence without mutating ipn_next_sequence" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 3, ipn_next_sequence: 10)
    assert_equal "MS-015", org.next_ipn(sequence: 15)
    assert_equal 10, org.ipn_next_sequence
  end

  test "ipn_preview returns the next reference plus a run of examples" do
    org = create_organization(ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 3, ipn_next_sequence: 1)
    preview = org.ipn_preview(example_count: 2)
    assert_equal "MS-001", preview[:next]
    assert_equal [ "MS-002", "MS-003" ], preview[:examples]
  end

  test "defaults to the incremental generation mode with a numeric charset" do
    org = create_organization
    assert_equal "incremental", org.ipn_generation_mode
    assert_equal "numeric", org.ipn_charset
  end

  test "rejects an unknown generation mode or charset" do
    org = create_organization
    org.ipn_generation_mode = "quantum"
    assert_not org.valid?
    assert_includes org.errors[:ipn_generation_mode], "is not included in the list"

    org.ipn_generation_mode = "random"
    org.ipn_charset = "emoji"
    assert_not org.valid?
    assert_includes org.errors[:ipn_charset], "is not included in the list"
  end

  test "category_sequence mode always includes the category and previews from 1" do
    org = create_organization(ipn_generation_mode: "category_sequence", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 99)
    preview = org.ipn_preview(category_code: "CAP", example_count: 2)
    assert_equal "MS-CAP-00001", preview[:next]
    assert_equal [ "MS-CAP-00002", "MS-CAP-00003" ], preview[:examples]
  end

  test "random mode draws a stable body from the configured charset" do
    org = create_organization(ipn_generation_mode: "random", ipn_charset: "numeric", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 6)
    first = org.next_ipn(sequence: 5)
    assert_match(/\AMS-\d{6}\z/, first)
    assert_equal first, org.next_ipn(sequence: 5), "same seed must reproduce the same reference"

    org.ipn_charset = "alphanumeric"
    assert_match(/\AMS-[A-Z0-9]{6}\z/, org.next_ipn(sequence: 5))
  end

  test "manual mode still produces an incremental suggested value" do
    org = create_organization(ipn_generation_mode: "manual", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 4, ipn_next_sequence: 12)
    assert_equal "MS-0012", org.ipn_preview[:next]
  end

  test "reassign_ipns! renumbers every part in creation order and advances the counter" do
    org = create_organization(ipn_generation_mode: "incremental", ipn_prefix: "MS", ipn_use_category_code: false, ipn_separator: "-", ipn_digits: 5, ipn_next_sequence: 50)
    category = create_category(organization: org)
    first = create_part(organization: org, category: category)
    second = create_part(organization: org, category: category)

    count = org.reassign_ipns!

    assert_equal 2, count
    assert_equal "MS-00001", first.reload.ipn
    assert_equal "MS-00002", second.reload.ipn
    assert_equal 3, org.reload.ipn_next_sequence
  end

  test "reassign_ipns! is a no-op in manual mode" do
    org = create_organization(ipn_generation_mode: "manual")
    part = create_part(organization: org, category: create_category(organization: org), ipn: "CUSTOM")

    assert_equal 0, org.reassign_ipns!
    assert_equal "CUSTOM", part.reload.ipn
  end

  test "rejects a currency outside the allowed set" do
    org = create_organization
    org.currency = "JPY"
    assert_not org.valid?
    assert_includes org.errors[:currency], "is not included in the list"
  end

  test "must have at least one owner on update" do
    org = create_organization
    user = User.create!(firstname: "A", lastname: "B", email: "owner_test@example.com", password: "password123")
    membership = OrganizationMembership.create!(organization: org, user: user, role: "owner")

    # Bypass OrganizationMembership's own destroy-guard (which independently
    # blocks removing the last owner) to exercise Organization's own check.
    OrganizationMembership.where(id: membership.id).delete_all
    org.reload

    assert_not org.update(name: "New name")
    assert_includes org.errors[:base], "Organization must have at least one owner"
  end

  test "destroy succeeds and cascades even with a sole active owner" do
    org = create_organization
    user = User.create!(firstname: "A", lastname: "B", email: "destroy_owner@example.com", password: "password123")
    OrganizationMembership.create!(organization: org, user: user, role: "owner")

    assert_difference [ -> { Organization.count }, -> { OrganizationMembership.count } ], -1 do
      assert org.destroy
    end
    assert org.destroyed?
  end

  test "low_stock_parts_count and out_of_stock_parts_count return integers, not hashes" do
    org = create_organization
    cat = create_category(organization: org)
    location = create_storage_location(organization: org)

    low = create_part(organization: org, category: cat, min_stock_threshold: 50)
    PartStorage.create!(part: low, storage_location: location, quantity: 5)

    out = create_part(organization: org, category: cat, min_stock_threshold: 10)
    PartStorage.create!(part: out, storage_location: location, quantity: 0)

    ok = create_part(organization: org, category: cat, min_stock_threshold: 10)
    PartStorage.create!(part: ok, storage_location: location, quantity: 100)

    assert_equal 2, org.low_stock_parts_count
    assert_kind_of Integer, org.low_stock_parts_count
    assert_equal 1, org.out_of_stock_parts_count
    assert_kind_of Integer, org.out_of_stock_parts_count
  end

  test "total_stock_units sums quantity across all parts and locations" do
    org = create_organization
    cat = create_category(organization: org)
    location = create_storage_location(organization: org)
    part_a = create_part(organization: org, category: cat)
    part_b = create_part(organization: org, category: cat)
    PartStorage.create!(part: part_a, storage_location: location, quantity: 30)
    PartStorage.create!(part: part_b, storage_location: location, quantity: 12)

    assert_equal 42, org.total_stock_units
  end

  test "total_stock_units is zero with no stock" do
    org = create_organization
    assert_equal 0, org.total_stock_units
  end

  test "category_breakdown returns counts sorted descending with pct relative to the max" do
    org = create_organization
    resistors = create_category(organization: org, name: "Resistors")
    capacitors = create_category(organization: org, name: "Capacitors")

    2.times { create_part(organization: org, category: capacitors) }
    4.times { create_part(organization: org, category: resistors) }

    breakdown = org.category_breakdown
    assert_equal [
      { name: "Resistors", count: 4, pct: 100 },
      { name: "Capacitors", count: 2, pct: 50 }
    ], breakdown
  end

  test "category_breakdown is empty with no parts" do
    org = create_organization
    assert_equal [], org.category_breakdown
  end

  test "seeds a supplier for every catalog provider on creation" do
    org = create_organization
    assert_equal Supplier::CATALOG_PROVIDERS.sort,
                 org.suppliers.catalog.pluck(:catalog_provider).sort
  end

  test "destroy removes a populated organization with stock, orders, and projects" do
    user = create_user
    org = create_organization
    OrganizationMembership.create!(organization: org, user: user, role: "owner")
    location = create_storage_location(organization: org)
    part = create_part(organization: org)
    org.stock_movements.create!(part: part, storage_location: location, movement_type: "in", quantity_delta: 5, user: user)
    line = create_order(organization: org, reference: "PO-1").order_lines.create!(part: part, quantity: 2)
    line.allocations.create!(storage_location: location, quantity: 2)
    create_project(organization: org).project_lines.create!(part: part, quantity: 1)

    assert org.destroy
    assert_not Organization.exists?(org.id)
    assert_equal 0, Part.where(organization_id: org.id).count
    assert_equal 0, StockMovement.where(organization_id: org.id).count
    assert_equal 0, Order.where(organization_id: org.id).count
  end

  test "the logo must be an image of at most 2 MB" do
    org = create_user.organizations.first # has an owner, so it's otherwise valid
    org.logo.attach(io: StringIO.new("a" * (2.megabytes + 1)), filename: "logo.png", content_type: "image/png", identify: false)
    assert_not org.valid?
    assert_match(/smaller than 2 MB/, org.errors[:logo].join)

    org.logo.attach(io: StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'/>"), filename: "logo.svg", content_type: "image/svg+xml", identify: false)
    assert org.valid?, "SVG logos are allowed"
  end

  test "timezone must be one of the zones Settings offers" do
    org = Organization.new(name: "Lab", timezone: "Mars/Olympus_Mons")
    assert_not org.valid?
    assert org.errors[:timezone].any?

    org.timezone = "America/New_York"
    org.valid?
    assert_empty org.errors[:timezone]
  end

  test "the default timezone is valid" do
    assert_includes Organization::TIMEZONES, Organization.new.timezone
  end

  test "replacing the DigiKey client id unlinks the connected account" do
    org = create_user.organizations.first
    org.update!(digikey_client_id: "app-1", digikey_client_secret: "s",
                digikey_access_token: "at", digikey_refresh_token: "rt", digikey_token_expires_at: 1.hour.from_now)

    org.update!(digikey_client_id: "app-2")

    assert_not org.reload.digikey_account_connected?
    assert_nil org.digikey_access_token
  end

  test "rotating only the DigiKey secret keeps the connected account" do
    org = create_user.organizations.first
    org.update!(digikey_client_id: "app-1", digikey_client_secret: "s",
                digikey_access_token: "at", digikey_refresh_token: "rt")

    org.update!(digikey_client_secret: "rotated")
    org.update!(digikey_client_id: "app-1")

    assert org.reload.digikey_account_connected?
  end
end

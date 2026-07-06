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

  test "viewers returns only users with the viewer role" do
    org = create_organization
    owner = User.create!(firstname: "O", lastname: "W", email: "owner2@example.com", password: "password123")
    viewer = User.create!(firstname: "V", lastname: "I", email: "viewer2@example.com", password: "password123")
    OrganizationMembership.create!(organization: org, user: owner, role: "owner")
    OrganizationMembership.create!(organization: org, user: viewer, role: "viewer")

    assert_equal [ viewer ], org.viewers.to_a
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
end

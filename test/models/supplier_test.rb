require "test_helper"

class SupplierTest < ActiveSupport::TestCase
  test "valid with just a name and organization" do
    org = create_organization
    assert Supplier.new(organization: org, name: "Acme Parts").valid?
  end

  test "accepts a known catalog_provider" do
    org = create_organization
    # The org is seeded with a mouser supplier, so clear it first to isolate
    # the inclusion check from the uniqueness one.
    org.suppliers.where(catalog_provider: "mouser").destroy_all
    supplier = org.suppliers.build(name: "Mouser", catalog_provider: "mouser")
    assert supplier.valid?, supplier.errors.full_messages.to_sentence
  end

  test "rejects an unknown catalog_provider" do
    org = create_organization
    supplier = org.suppliers.build(name: "Nope", catalog_provider: "farnell")
    assert_not supplier.valid?
    assert_includes supplier.errors[:catalog_provider], "is not included in the list"
  end

  test "allows a nil catalog_provider" do
    org = create_organization
    assert org.suppliers.build(name: "Generic", catalog_provider: nil).valid?
  end

  test "catalog_provider is unique per organization" do
    org = create_organization
    # The org already has a seeded mouser supplier, so a second one is invalid.
    dup = org.suppliers.build(name: "Mouser Duplicate", catalog_provider: "mouser")
    assert_not dup.valid?
    assert_includes dup.errors[:catalog_provider], "has already been taken"
  end

  test "the same catalog_provider is allowed across organizations" do
    org_a = create_organization
    org_b = create_organization
    # Both orgs get seeded independently without a uniqueness collision.
    assert_equal 1, org_a.suppliers.where(catalog_provider: "mouser").count
    assert_equal 1, org_b.suppliers.where(catalog_provider: "mouser").count
  end

  test "ensure_catalog_provider returns the existing supplier without creating" do
    org = create_organization
    existing = org.suppliers.find_by(catalog_provider: "mouser")

    supplier, created = nil
    assert_no_difference -> { org.suppliers.count } do
      supplier, created = Supplier.ensure_catalog_provider(org, "mouser")
    end

    assert_equal existing, supplier
    assert_not created
  end

  test "ensure_catalog_provider creates the supplier when missing" do
    org = create_organization
    org.suppliers.where(catalog_provider: "mouser").destroy_all

    supplier, created = nil
    assert_difference -> { org.suppliers.count } => 1 do
      supplier, created = Supplier.ensure_catalog_provider(org, "mouser")
    end

    assert created
    assert_equal "Mouser Electronics", supplier.name
    assert_equal "mouser", supplier.catalog_provider
  end

  test "ensure_catalog_provider adopts an untagged same-named supplier" do
    org = create_organization
    seeded = org.suppliers.find_by(catalog_provider: "mouser")
    seeded.update_column(:catalog_provider, nil)

    supplier, created = nil
    assert_no_difference -> { org.suppliers.count } do
      supplier, created = Supplier.ensure_catalog_provider(org, "mouser")
    end

    assert_not created
    assert_equal seeded, supplier
    assert_equal "mouser", supplier.reload.catalog_provider
  end

  test "catalog? reflects the provider tag" do
    org = create_organization
    assert org.suppliers.find_by(catalog_provider: "digikey").catalog?
    assert_not org.suppliers.build(name: "Plain").catalog?
  end
end

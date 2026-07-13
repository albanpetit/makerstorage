require "test_helper"

class SupplierCatalogTest < ActiveSupport::TestCase
  test "provider_for returns a Mouser provider when a key is configured" do
    org = create_organization(mouser_api_key: "abc123")
    assert_instance_of SupplierCatalog::Mouser, SupplierCatalog.provider_for(org)
  end

  test "provider_for returns nil when no credentials are set" do
    org = create_organization
    assert_nil SupplierCatalog.provider_for(org)
  end

  test "lookup raises NotConfiguredError when no provider is configured" do
    org = create_organization
    assert_raises(SupplierCatalog::NotConfiguredError) { SupplierCatalog.lookup(org, mpn: "x") }
  end

  test "lookup delegates to the configured provider" do
    org = create_organization(mouser_api_key: "abc123")
    fake = Object.new
    fake.define_singleton_method(:search) { |mpn| [ mpn ] }

    stub_singleton(SupplierCatalog, :provider_for, ->(*) { fake }) do
      assert_equal [ "RC0805" ], SupplierCatalog.lookup(org, mpn: "RC0805")
    end
  end

  test "mouser_api_key is stored encrypted at rest" do
    org = create_organization(mouser_api_key: "super-secret-key")
    raw = Organization.connection.select_value("SELECT mouser_api_key FROM organizations WHERE id = #{org.id}")

    refute_equal "super-secret-key", raw
    assert_equal "super-secret-key", org.reload.mouser_api_key
  end
end

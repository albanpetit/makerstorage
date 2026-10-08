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

  test "providers_for includes a Digikey provider when both credentials are set" do
    org = create_organization(digikey_client_id: "cid", digikey_client_secret: "csecret")
    assert_equal [ SupplierCatalog::Digikey ], SupplierCatalog.providers_for(org).map(&:class)
  end

  test "providers_for ignores DigiKey when only one credential half is present" do
    org = create_organization(digikey_client_id: "cid")
    assert_empty SupplierCatalog.providers_for(org)
  end

  test "providers_for returns both providers when Mouser and DigiKey are configured" do
    org = create_organization(mouser_api_key: "abc123", digikey_client_id: "cid", digikey_client_secret: "csecret")
    assert_equal [ SupplierCatalog::Mouser, SupplierCatalog::Digikey ], SupplierCatalog.providers_for(org).map(&:class)
  end

  test "lookup merges results from every configured provider" do
    org = create_organization(mouser_api_key: "abc123", digikey_client_id: "cid", digikey_client_secret: "csecret")
    mouser = fake_provider([ "from-mouser" ])
    digikey = fake_provider([ "from-digikey" ])

    stub_singleton(SupplierCatalog, :providers_for, ->(*) { [ mouser, digikey ] }) do
      assert_equal [ "from-mouser", "from-digikey" ], SupplierCatalog.lookup(org, mpn: "x")
    end
  end

  test "lookup still returns results when one provider fails" do
    org = create_organization
    ok = fake_provider([ "ok" ])
    boom = Object.new
    boom.define_singleton_method(:search) { |_| raise SupplierCatalog::LookupError, "down" }

    stub_singleton(SupplierCatalog, :providers_for, ->(*) { [ boom, ok ] }) do
      assert_equal [ "ok" ], SupplierCatalog.lookup(org, mpn: "x")
    end
  end

  test "lookup raises when every provider fails" do
    org = create_organization
    boom = Object.new
    boom.define_singleton_method(:search) { |_| raise SupplierCatalog::LookupError, "down" }

    stub_singleton(SupplierCatalog, :providers_for, ->(*) { [ boom ] }) do
      error = assert_raises(SupplierCatalog::LookupError) { SupplierCatalog.lookup(org, mpn: "x") }
      assert_equal "down", error.message
    end
  end

  test "lookup raises NotConfiguredError when no provider is configured" do
    org = create_organization
    assert_raises(SupplierCatalog::NotConfiguredError) { SupplierCatalog.lookup(org, mpn: "x") }
  end

  test "lookup delegates to the configured provider" do
    org = create_organization(mouser_api_key: "abc123")
    fake = Object.new
    fake.define_singleton_method(:search) { |mpn| [ mpn ] }

    stub_singleton(SupplierCatalog, :providers_for, ->(*) { [ fake ] }) do
      assert_equal [ "RC0805" ], SupplierCatalog.lookup(org, mpn: "RC0805")
    end
  end

  test "mouser_api_key is stored encrypted at rest" do
    org = create_organization(mouser_api_key: "super-secret-key")
    raw = Organization.connection.select_value("SELECT mouser_api_key FROM organizations WHERE id = #{org.id}")

    refute_equal "super-secret-key", raw
    assert_equal "super-secret-key", org.reload.mouser_api_key
  end

  test "digikey credentials are stored encrypted at rest" do
    org = create_organization(digikey_client_id: "public-id", digikey_client_secret: "super-secret")
    raw_id = Organization.connection.select_value("SELECT digikey_client_id FROM organizations WHERE id = #{org.id}")
    raw_secret = Organization.connection.select_value("SELECT digikey_client_secret FROM organizations WHERE id = #{org.id}")

    refute_equal "public-id", raw_id
    refute_equal "super-secret", raw_secret
    assert_equal "public-id", org.reload.digikey_client_id
    assert_equal "super-secret", org.digikey_client_secret
  end

  # An organization with a linked DigiKey account whose access token expired.
  # Saved without validation: a bare test organization has no owner, which the
  # update validation requires.
  def org_with_expired_digikey_token
    org = create_organization
    org.assign_attributes(
      digikey_client_id: "c", digikey_client_secret: "s",
      digikey_access_token: "old-a", digikey_refresh_token: "old-r", digikey_token_expires_at: 1.minute.ago
    )
    org.save!(validate: false)
    org
  end

  test "digikey_order_client uses tokens a concurrent request refreshed first" do
    org = org_with_expired_digikey_token

    # Another request refreshes (rotating the refresh token) while ours is in
    # flight, so DigiKey rejects ours.
    concurrent_refresh = lambda do |**|
      Organization.find(org.id).tap do |other|
        other.digikey_access_token = "fresh-a"
        other.digikey_refresh_token = "fresh-r"
        other.digikey_token_expires_at = 30.minutes.from_now
        other.save!(validate: false)
      end
      raise SupplierCatalog::LookupError, "DigiKey rejected the authorization."
    end

    client = stub_singleton(SupplierCatalog::Digikey, :refresh_token, concurrent_refresh) do
      SupplierCatalog.digikey_order_client(org)
    end

    assert_equal "fresh-a", client.instance_variable_get(:@access_token)
  end

  test "digikey_order_client still reports a refresh nobody else recovered from" do
    org = org_with_expired_digikey_token

    rejected = ->(**) { raise SupplierCatalog::LookupError, "DigiKey rejected the authorization." }
    stub_singleton(SupplierCatalog::Digikey, :refresh_token, rejected) do
      assert_raises(SupplierCatalog::LookupError) { SupplierCatalog.digikey_order_client(org) }
    end
  end

  private

  # A stand-in provider whose #search always yields the given results.
  def fake_provider(results)
    provider = Object.new
    provider.define_singleton_method(:search) { |_mpn| results }
    provider
  end
end

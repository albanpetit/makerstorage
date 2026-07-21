# frozen_string_literal: true

# Looks up electronic-component data from external supplier catalogs (Mouser,
# DigiKey, and future providers) by manufacturer part number, returning
# normalized results that map onto our Part model.
#
#   SupplierCatalog.lookup(organization, mpn: "RC0805FR-0710KL")
#   # => [ SupplierCatalog::PartResult, ... ]
#
# Raises SupplierCatalog::NotConfiguredError when the organization has no
# provider credentials, and SupplierCatalog::LookupError on upstream failures.
module SupplierCatalog
  # Base for all catalog errors so callers can rescue the whole family.
  class Error < StandardError; end

  # No provider is configured for the organization.
  class NotConfiguredError < Error; end

  # The upstream provider request failed (network, auth, bad response...).
  class LookupError < Error; end

  # A supplier order fetched from a provider's order API, normalized across
  # providers. +lines+ is an Array<OrderLineResult>.
  OrderResult = Struct.new(:order_number, :status, :placed_at, :total, :currency, :lines, keyword_init: true)

  # One line of a fetched supplier order, or a priced line of a built cart.
  OrderLineResult = Struct.new(
    :mpn, :manufacturer, :supplier_sku, :description, :quantity, :unit_price,
    keyword_init: true
  )

  # The outcome of building a cart at the supplier: its key, a checkout handoff
  # URL when the provider returns one, and the priced lines.
  CartResult = Struct.new(:cart_key, :checkout_url, :currency, :merchandise_total, :lines, keyword_init: true)

  module_function

  # A Mouser client wired for the Order/Cart API (push-to-cart, order import),
  # or nil when the organization hasn't configured the order key. Distinct from
  # the Search API providers above — the two use different Mouser keys.
  def mouser_order_client(organization)
    return nil unless organization.mouser_order_configured?

    Mouser.new(api_key: organization.mouser_api_key, order_api_key: organization.mouser_order_api_key)
  end

  # Returns an Array<PartResult> (possibly empty) for the given part number,
  # merged across every configured provider so the user sees matches from all of
  # them in one pick-list. A single provider failing doesn't sink the lookup —
  # its error is only surfaced when *every* provider failed to return anything.
  def lookup(organization, mpn:)
    providers = providers_for(organization)
    raise NotConfiguredError, "No supplier catalog is configured for this organization" if providers.empty?

    results = []
    errors = []

    providers.each do |provider|
      results.concat(provider.search(mpn))
    rescue LookupError => e
      errors << e
    end

    raise errors.first if results.empty? && errors.any?

    results
  end

  # Every configured provider for an organization, in preference order. Empty
  # when none is set.
  def providers_for(organization)
    providers = []
    providers << Mouser.new(api_key: organization.mouser_api_key) if organization.mouser_api_key.present?
    if organization.digikey_configured?
      providers << Digikey.new(
        client_id: organization.digikey_client_id,
        client_secret: organization.digikey_client_secret
      )
    end
    providers
  end

  # The first configured provider, or nil when none is set.
  def provider_for(organization)
    providers_for(organization).first
  end
end

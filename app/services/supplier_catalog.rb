# frozen_string_literal: true

# Looks up electronic-component data from external supplier catalogs (Mouser,
# and future providers) by manufacturer part number, returning normalized
# results that map onto our Part model.
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

  module_function

  # Returns an Array<PartResult> (possibly empty) for the given part number.
  def lookup(organization, mpn:)
    provider = provider_for(organization)
    raise NotConfiguredError, "No supplier catalog is configured for this organization" unless provider

    provider.search(mpn)
  end

  # Picks the configured provider for an organization, or nil when none is set.
  def provider_for(organization)
    if organization.mouser_api_key.present?
      Mouser.new(api_key: organization.mouser_api_key)
    end
  end
end

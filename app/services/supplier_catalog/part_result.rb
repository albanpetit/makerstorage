# frozen_string_literal: true

module SupplierCatalog
  # A single normalized catalog match, provider-agnostic. Fields line up with
  # the columns the add-part form fills in; +datasheet_url+/+image_url+ are
  # downloaded and attached server-side on create (never trusting the client).
  PartResult = Struct.new(
    :name,
    :mpn,
    :manufacturer,
    :description,
    :value,
    :package_type,
    :tolerance,
    :voltage_rating,
    :power_rating,
    :unit_price,
    :rohs_compliant,
    :datasheet_url,
    :image_url,
    :product_url,
    :supplier_sku,
    :provider,
    :attributes,
    keyword_init: true
  ) do
    # Shape sent to the frontend. The datasheet/image URLs are echoed so the
    # client can preview them and hand them back on submit for attachment.
    def as_json(*)
      {
        name: name,
        mpn: mpn,
        manufacturer: manufacturer,
        description: description,
        value: value,
        package_type: package_type,
        tolerance: tolerance,
        voltage_rating: voltage_rating,
        power_rating: power_rating,
        unit_price: unit_price,
        rohs_compliant: rohs_compliant,
        datasheet_url: datasheet_url,
        image_url: image_url,
        product_url: product_url,
        supplier_sku: supplier_sku,
        provider: provider,
        attributes: attributes
      }
    end
  end
end

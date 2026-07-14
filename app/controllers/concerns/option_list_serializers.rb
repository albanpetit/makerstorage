require "active_support/concern"

# Shared serializers for the "option list" payloads (categories, footprints,
# tags, suppliers, storage locations, parts) that several controllers hand to
# Inertia to populate select inputs and pickers. Keeping them in one place means
# a shape change only has to be made once.
#
# All of these read from `current_organization`, so every including controller
# must expose that method (ApplicationController does).
module OptionListSerializers
  extend ActiveSupport::Concern

  private

  def serialize_categories
    current_organization.categories.alphabetical.map do |category|
      { id: category.id, name: category.full_path }
    end
  end

  def serialize_footprints
    current_organization.footprints.alphabetical.map do |footprint|
      { id: footprint.id, name: footprint.name, mounting_type: footprint.mounting_type }
    end
  end

  def serialize_suppliers
    current_organization.suppliers.order(:name).map do |supplier|
      { id: supplier.id, name: supplier.name, website: supplier.website, catalog_provider: supplier.catalog_provider }
    end
  end

  def serialize_tags
    current_organization.tags.alphabetical.map do |tag|
      { id: tag.id, name: tag.name, color: tag.color }
    end
  end

  def serialize_storage_locations
    locations = current_organization.storage_locations.alphabetical
    cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    locations.map do |location|
      { id: location.id, name: location.full_path(cache: cache) }
    end
  end
end

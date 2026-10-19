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

  # Sorted by full path so the list reads as a tree (each parent directly
  # followed by its children). `name` is the full path ("Passives > Resistors"),
  # `short_name` the category's own name.
  def serialize_categories
    categories = current_organization.categories.to_a
    cache = categories.index_by(&:id)
    categories
      .map { |category| [ category, category.path_names(cache: cache) ] }
      .sort_by { |_category, path| path.map(&:downcase) }
      .map { |category, path| serialize_category_option(category, path) }
  end

  def serialize_category_option(category, path = category.path_names)
    {
      id: category.id,
      name: path.join(" > "),
      short_name: category.name,
      parent_id: category.parent_id,
      depth: path.size - 1,
      code: category.code
    }
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

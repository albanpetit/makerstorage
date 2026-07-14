# frozen_string_literal: true

# Backs the dashboard's "search everywhere" box: a lightweight JSON endpoint
# (not Inertia) queried on keystroke, returning parts and storage zones of the
# current organization grouped for the results dropdown.
class SearchController < ApplicationController
  include Auth

  before_action :verify_organization_access

  MIN_QUERY_LENGTH = 2
  RESULT_LIMIT = 6

  def index
    query = params[:q].to_s.strip

    if query.length < MIN_QUERY_LENGTH
      render json: { parts: [], zones: [] }
      return
    end

    render json: { parts: search_parts(query), zones: search_zones(query) }
  end

  private

  def search_parts(query)
    current_organization.parts
      .includes(:category)
      .search(query)
      .alphabetical
      .limit(RESULT_LIMIT)
      .map do |part|
        {
          id: part.id,
          reference: part.mpn.presence || part.sku.presence || part.name,
          name: part.name,
          category: part.category&.name
        }
      end
  end

  def search_zones(query)
    q = "%#{StorageLocation.sanitize_sql_like(query)}%"

    current_organization.storage_locations
      .where("name LIKE :q ESCAPE '\\' OR code LIKE :q ESCAPE '\\'", q: q)
      .alphabetical
      .limit(RESULT_LIMIT)
      .map do |zone|
        {
          id: zone.id,
          name: zone.name,
          path: zone.full_path,
          location_type: zone.location_type
        }
      end
  end
end

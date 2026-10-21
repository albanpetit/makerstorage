# frozen_string_literal: true

# KiCad HTTP library endpoints (see KicadLibrary): read-only, authenticated by
# the organization's KiCad token rather than a user session.
class KicadLibraryController < ActionController::API
  before_action :authenticate_token!

  def index
    root = "#{request.base_url}/kicad/#{KicadLibrary::API_VERSION}"
    render json: { categories: "#{root}/categories.json", parts: "#{root}/parts" }
  end

  def categories
    render json: library.categories
  end

  def category_parts
    parts = library.category_parts(params[:category_id])
    parts ? render(json: parts) : not_found
  end

  def part
    part = library.part(params[:id])
    part ? render(json: part) : not_found
  end

  private

  def library
    @library ||= KicadLibrary.new(@organization, base_url: request.base_url)
  end

  # KiCad sends "Authorization: Token <token>"; Bearer is accepted too.
  def authenticate_token!
    token = request.authorization.to_s[/\A(?:Token|Bearer) (.+)\z/, 1]
    @organization = KicadLibrary.authenticate(token)
    render json: { error: "unauthorized" }, status: :unauthorized unless @organization
  end

  def not_found
    render json: { error: "not found" }, status: :not_found
  end
end

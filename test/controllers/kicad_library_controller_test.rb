require "test_helper"

class KicadLibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = create_organization
    @category = create_category(organization: @org, name: "Resistors")
    @part = create_part(organization: @org, category: @category, name: "10k 0603", value: "10k")
    @token = KicadLibrary.issue_token!(@org)
  end

  test "every endpoint refuses a missing or wrong token" do
    [ "/kicad/v1/", "/kicad/v1/categories.json", "/kicad/v1/parts/category/#{@category.id}.json", "/kicad/v1/parts/#{@part.id}.json" ].each do |path|
      get path
      assert_response :unauthorized, path
      get path, headers: auth("mskicad_nope")
      assert_response :unauthorized, path
    end
  end

  test "a revoked token is refused" do
    KicadLibrary.revoke_token!(@org)
    get "/kicad/v1/categories.json", headers: auth(@token)
    assert_response :unauthorized
  end

  test "the root answers KiCad's endpoint check, with or without a doubled slash" do
    [ "/kicad/v1/", "/kicad//v1/", "/kicad/" ].each do |path|
      get path, headers: auth(@token)
      assert_response :success, path
      body = response.parsed_body
      assert body["categories"].present? && body["parts"].present?, path
    end
  end

  test "lists categories, a category's parts and a part" do
    get "/kicad/v1/categories.json", headers: auth(@token)
    assert_response :success
    assert_equal [ @category.id.to_s ], response.parsed_body.map { |row| row["id"] }

    get "/kicad/v1/parts/category/#{@category.id}.json", headers: auth(@token)
    assert_response :success
    assert_equal [ { "id" => @part.id.to_s, "name" => "10k 0603", "description" => "Stock: 0" } ], response.parsed_body

    get "/kicad/v1/parts/#{@part.id}.json", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
    assert_equal "Device:R", response.parsed_body["symbolIdStr"]
    assert_equal "10k", response.parsed_body.dig("fields", "value", "value")
  end

  test "another organization's category and part are not found" do
    other = create_organization
    foreign_category = create_category(organization: other, name: "Resistors")
    foreign_part = create_part(organization: other, category: foreign_category)

    get "/kicad/v1/parts/category/#{foreign_category.id}.json", headers: auth(@token)
    assert_response :not_found
    get "/kicad/v1/parts/#{foreign_part.id}.json", headers: auth(@token)
    assert_response :not_found
  end

  private

  def auth(token)
    { "Authorization" => "Token #{token}" }
  end
end

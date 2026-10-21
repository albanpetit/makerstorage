require "test_helper"

# Parameters through the part form and the inventory list (PartsController).
class PartsParametersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    @tolerance = @org.parameter_definitions.create!(name: "Tolerance", unit: "%")
    @dielectric = @org.parameter_definitions.create!(name: "Dielectric", value_type: "text")
    @resistors = create_category(organization: @org, name: "Resistors")
    @resistors.update!(parameter_template: [ @resistance.id, @tolerance.id ])
    sign_in @user
  end

  def values(part)
    part.reload.part_parameters.includes(:parameter_definition).to_h { |p| [ p.name, p.value ] }
  end

  test "create saves the parameters sent with the part" do
    post parts_path, params: { part: { name: "Resistor 4k7", category_id: @resistors.id,
                                       parameter_values: { @resistance.id => "4k7", @tolerance.id => "1%", @dielectric.id => "" } } }

    assert_redirected_to parts_path
    assert_equal({ "Resistance" => "4k7", "Tolerance" => "1%" }, values(@org.parts.find_by!(name: "Resistor 4k7")))
  end

  test "update changes and removes parameters, and leaves the others alone" do
    part = create_part(organization: @org, category: @resistors)
    part.update!(parameter_values: { @resistance.id => "10k", @dielectric.id => "X7R" })

    patch part_path(part), params: { part: { parameter_values: { @resistance.id => "22k", @tolerance.id => "" } } }

    assert_equal({ "Resistance" => "22k", "Dielectric" => "X7R" }, values(part))
  end

  test "a value that isn't a number in the unit comes back as a form error" do
    part = create_part(organization: @org, name: "Kept")

    patch part_path(part), params: { part: { name: "Changed", parameter_values: { @resistance.id => "lots" } } }

    follow_redirect!
    assert_equal [ "Resistance: “lots” is not a value in Ω" ], inertia_props.dig("errors", "part.parameters")
    assert_equal "Kept", part.reload.name
  end

  test "another organization's parameter is ignored" do
    foreign = create_organization.parameter_definitions.create!(name: "Gain", unit: "dB")
    part = create_part(organization: @org)

    patch part_path(part), params: { part: { parameter_values: { foreign.id => "20" } } }

    assert_empty part.part_parameters.reload
  end

  test "the edit payload and list rows carry the parameters, with their canonical form" do
    part = create_part(organization: @org, category: @resistors, name: "R1")
    part.update!(parameter_values: { @resistance.id => "4k7" })

    get edit_part_path(part), as: :json
    assert_equal [ { "id" => @resistance.id, "name" => "Resistance", "value" => "4k7", "display" => "4.7 kΩ" } ],
                 response.parsed_body.dig("part", "parameters")

    get parts_path(category: @resistors.id)
    row = inertia_props["parts"].find { |p| p["id"] == part.id }
    assert_equal "4.7 kΩ", row["parameters"].first["display"]
    assert_equal %w[Resistance Tolerance], inertia_props["parameter_columns"].map { |c| c["name"] }
  end

  test "the list filters on a parameter range typed like a part value" do
    small = create_part(organization: @org, category: @resistors, name: "Small", value: "1k")
    big = create_part(organization: @org, category: @resistors, name: "Big", value: "100k")

    get parts_path(param: { @resistance.id => { min: "10k", max: "1M" } })

    assert_equal [ big.id ], inertia_props["matching_ids"]
    filter = inertia_props.dig("filters", "parameters").first
    assert_equal [ "10k", "1M", "10 kΩ", "1 MΩ", false ], filter.values_at("min", "max", "min_display", "max_display", "invalid")
    facet = inertia_props.dig("facets", "parameters").find { |f| f["id"] == @resistance.id }
    assert_equal [ 2, "1 kΩ", "100 kΩ" ], facet.values_at("count", "min_display", "max_display")

    post rows_parts_path, params: { filters: { parameters: [ { id: @resistance.id, max: "10k" } ] } }, as: :json
    assert_equal [ small.id ], response.parsed_body["parts"].map { |p| p["id"] }
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

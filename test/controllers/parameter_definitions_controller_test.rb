require "test_helper"

class ParameterDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  test "redirects a signed-out visitor to login" do
    get parameter_definitions_path
    assert_redirected_to new_user_session_path
  end

  test "index lists the organization's parameters with usage and templates" do
    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    @org.parameter_definitions.create!(name: "Dielectric", value_type: "text")
    create_organization.parameter_definitions.create!(name: "Foreign")
    category = create_category(organization: @org, name: "Resistors")
    category.update!(parameter_template: [ resistance.id ])
    create_part(organization: @org, category: category, value: "10k")

    sign_in @user
    get parameter_definitions_path
    assert_response :success

    definitions = inertia_props["definitions"]
    assert_equal %w[Dielectric Resistance], definitions.map { |d| d["name"] }
    row = definitions.last
    assert_equal [ "number", "Ω", 1, [ "Resistors" ] ], row.values_at("value_type", "unit", "parts_count", "category_names")
    assert_equal ParameterDefinition::STANDARD.size - 2, inertia_props["standard_missing"]
  end

  test "index as JSON gives the part form every parameter and the inherited templates" do
    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    parent = create_category(organization: @org, name: "Passives")
    child = create_category(organization: @org, name: "Resistors", parent: parent)
    parent.update!(parameter_template: [ resistance.id ])

    sign_in @user
    get parameter_definitions_path, as: :json

    assert_equal [ { "id" => resistance.id, "name" => "Resistance", "value_type" => "number", "unit" => "Ω" } ],
                 response.parsed_body["definitions"]
    assert_equal [ resistance.id ], response.parsed_body["templates"][child.id.to_s]
  end

  test "create adds a parameter, as JSON for the part form too" do
    sign_in @user
    post parameter_definitions_path, params: { parameter_definition: { name: "Gain", unit: "dB" } }
    assert_redirected_to parameter_definitions_path

    post parameter_definitions_path, params: { parameter_definition: { name: "Package height", unit: "mm" } }, as: :json
    assert_response :created
    assert_equal "Package height", response.parsed_body.dig("definition", "name")
    assert_equal %w[Gain Package\ height], @org.parameter_definitions.alphabetical.pluck(:name)

    post parameter_definitions_path, params: { parameter_definition: { name: "gain" } }, as: :json
    assert_response :unprocessable_content
    assert_match(/already been taken/, response.parsed_body["errors"]["name"])
  end

  test "update changes a parameter and reports values that no longer fit" do
    definition = @org.parameter_definitions.create!(name: "Label", value_type: "text")
    create_part(organization: @org).part_parameters.create!(parameter_definition: definition, value: "blue")

    sign_in @user
    patch parameter_definition_path(definition), params: { parameter_definition: { name: "Colour" } }
    assert_equal "Colour", definition.reload.name

    patch parameter_definition_path(definition), params: { parameter_definition: { value_type: "number" } }
    assert_equal "text", definition.reload.value_type
    assert_match(/not a number/, inertia_errors["parameter_definition.base"].to_s)
  end

  test "destroy deletes a parameter and its values" do
    definition = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    create_part(organization: @org).part_parameters.create!(parameter_definition: definition, value: "1k")

    sign_in @user
    assert_difference -> { PartParameter.count } => -1, -> { ParameterDefinition.count } => -1 do
      delete parameter_definition_path(definition)
    end
    assert_match(/with its 1 part value/, flash[:notice])
  end

  test "standard installs the standard set" do
    create_category(organization: @org, name: "Capacitors")

    sign_in @user
    post standard_parameter_definitions_path

    assert_redirected_to parameter_definitions_path
    assert_equal ParameterDefinition::STANDARD.size, @org.parameter_definitions.count
    assert_match(/10 parameters added, 1 category given a template/, flash[:notice])
  end

  test "another organization's parameters can't be changed" do
    foreign = create_organization.parameter_definitions.create!(name: "Foreign")

    sign_in @user
    patch parameter_definition_path(foreign), params: { parameter_definition: { name: "Mine" } }
    assert_response :not_found
    assert_equal "Foreign", foreign.reload.name

    sign_in @user
    delete parameter_definition_path(foreign)
    assert_response :not_found
    assert ParameterDefinition.exists?(foreign.id)
  end

  test "viewers can read but not change parameters" do
    definition = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")

    sign_in viewer
    post switch_organization_path(@org)
    get parameter_definitions_path, as: :json
    assert_response :success

    assert_no_difference -> { ParameterDefinition.count } do
      post parameter_definitions_path, params: { parameter_definition: { name: "Gain" } }
      post standard_parameter_definitions_path
      delete parameter_definition_path(definition)
    end
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  def inertia_errors
    follow_redirect!
    inertia_props["errors"] || {}
  end
end

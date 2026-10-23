require "test_helper"

class PartAlternativesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @part = create_part(organization: @org, category: @category, name: "NE555P", mpn: "NE555P")
    @other = create_part(organization: @org, category: @category, name: "LM555", mpn: "LM555CN")
    @zone = create_storage_location(organization: @org)
    StockMovement.create!(organization: @org, part: @other, storage_location: @zone, movement_type: "in", quantity_delta: 12)
  end

  test "links and unlinks an alternative, shown on both parts' sheets" do
    sign_in @user

    assert_difference -> { PartAlternative.count } do
      post part_alternatives_path(@part), params: { alternative_part_id: @other.id, note: "pin compatible" },
                                          headers: { "Referer" => parts_url }
    end
    assert_redirected_to parts_url
    assert_equal "LM555 linked as an alternative.", flash[:notice]

    get part_path(@part), headers: { "Accept" => "application/json" }
    entry = response.parsed_body["alternatives"].sole
    assert_equal [ @other.id, "LM555CN", 12, "pin compatible" ], [ entry["part"]["id"], entry["part"]["reference"], entry["part"]["total_quantity"], entry["note"] ]

    get part_path(@other), headers: { "Accept" => "application/json" }
    assert_equal @part.id, response.parsed_body["alternatives"].sole["part"]["id"]

    delete part_alternative_path(@other, entry["id"])
    assert_equal "NE555P is no longer an alternative.", flash[:notice]
    assert_equal 0, PartAlternative.count
  end

  test "the picker lists the other parts not linked yet, obsolete ones left out" do
    linked = create_part(organization: @org, category: @category, name: "TLC555")
    create_part(organization: @org, category: @category, name: "Old 555", status: "obsolete")
    PartAlternative.link!(@part, linked)
    sign_in @user

    get part_alternatives_path(@part), headers: { "Accept" => "application/json" }

    assert_equal [ "LM555" ], response.parsed_body["parts"].map { |p| p["name"] }
  end

  test "the sheet suggests equivalents from the parameters" do
    resistance = @org.parameter_definitions.create!(name: "Resistance", unit: "Ω")
    r1 = create_part(organization: @org, category: @category, name: "10k a")
    r2 = create_part(organization: @org, category: @category, name: "10k b")
    r1.update!(parameter_values: { resistance.id => "10k" })
    r2.update!(parameter_values: { resistance.id => "10 kΩ" })
    sign_in @user

    get part_path(r1), headers: { "Accept" => "application/json" }

    suggestion = response.parsed_body["equivalents"].sole
    assert_equal [ r2.id, [ "Resistance" ] ], [ suggestion["part"]["id"], suggestion["matched"] ]
  end

  test "refuses a part of another organization, itself, and viewers" do
    foreign = create_part(organization: create_organization)
    sign_in @user

    post part_alternatives_path(@part), params: { alternative_part_id: @part.id }
    assert_equal "Alternative part must be another part", flash[:alert]

    post part_alternatives_path(@part), params: { alternative_part_id: foreign.id }
    assert_response :not_found

    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    post part_alternatives_path(@part), params: { alternative_part_id: @other.id }
    assert_equal 0, PartAlternative.count
    get part_alternatives_path(@part), headers: { "Accept" => "application/json" }
    assert_response :success
  end

  test "can't unlink through a part the link doesn't involve" do
    third = create_part(organization: @org, category: @category)
    link = PartAlternative.link!(@part, @other)
    sign_in @user

    delete part_alternative_path(third, link)

    assert_response :not_found
    assert PartAlternative.exists?(link.id)
  end
end

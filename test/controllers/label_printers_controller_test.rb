require "test_helper"

class LabelPrintersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @printer = @org.label_printers.create!(name: "Workshop QL", protocol: "brother_ql", host: "192.168.1.50", media: "62x29")
    sign_in @user
  end

  def bitmap(printer = @printer)
    Base64.strict_encode64("\x00".b * printer.bitmap_bytesize)
  end

  def join_as(role)
    member = create_user
    OrganizationMembership.create!(organization: @org, user: member, role: role)
    sign_in member
    post switch_organization_path(@org)
    member
  end

  test "index lists the organization's printers with their geometry" do
    create_organization.label_printers.create!(name: "Elsewhere", protocol: "brother_ql", host: "10.0.0.2", media: "62x29")

    get label_printers_path, as: :json
    assert_response :success
    body = response.parsed_body
    assert body["enabled"]
    assert_equal [ "Workshop QL" ], body["printers"].map { |p| p["name"] }
    assert_equal({ "id" => @printer.id, "name" => "Workshop QL", "size" => "62 × 29 mm", "width" => 696, "height" => 271 },
                 body["printers"].first.except("dots_per_mm"))
  end

  test "an admin adds, edits and removes printers" do
    assert_difference -> { @org.label_printers.count } do
      post label_printers_path, params: { label_printer: { name: "Zebra", protocol: "zpl", host: "192.168.1.60", port: 9100,
                                                           width_mm: 50.8, length_mm: 25.4, dpi: 203 } }
    end
    assert_redirected_to settings_path(section: "printers")

    patch label_printer_path(@printer), params: { label_printer: { media: "29x90" } }
    assert_equal "29x90", @printer.reload.media

    assert_difference -> { @org.label_printers.count }, -1 do
      delete label_printer_path(@printer)
    end
  end

  test "an invalid printer comes back with errors" do
    assert_no_difference -> { LabelPrinter.count } do
      post label_printers_path, params: { label_printer: { name: "", protocol: "brother_ql", host: "192.168.1.70", port: 22, media: "62x29" } }
    end
    follow_redirect!
    assert inertia_props["errors"].key?("label_printer.port")
  end

  test "members can't manage printers" do
    join_as("member")
    assert_no_difference -> { LabelPrinter.count } do
      post label_printers_path, params: { label_printer: { name: "Mine", protocol: "brother_ql", host: "192.168.1.70", media: "62x29" } }
    end
    patch label_printer_path(@printer), params: { label_printer: { host: "192.168.1.99" } }
    assert_equal "192.168.1.50", @printer.reload.host
  end

  test "another organization's printer is out of reach" do
    other = create_organization.label_printers.create!(name: "Other", protocol: "brother_ql", host: "10.0.0.2", media: "62x29")
    post print_label_printer_path(other), params: { labels: [ bitmap(other) ] }, as: :json
    assert_response :not_found
  end

  test "print sends the labels to the printer" do
    sent = nil
    stub_singleton(LabelPrinting::Network, :deliver, ->(host, port, data) { sent = [ host, port, data ] }) do
      post print_label_printer_path(@printer), params: { labels: [ bitmap, bitmap ] }, as: :json
    end

    assert_response :success
    assert_equal 2, response.parsed_body["printed"]
    assert_equal [ "192.168.1.50", 9100 ], sent.first(2)
    assert_equal 2, sent.last.scan("\x1A".b).size
  end

  test "a member can print" do
    join_as("member")
    stub_singleton(LabelPrinting::Network, :deliver, ->(*) { true }) do
      post print_label_printer_path(@printer), params: { labels: [ bitmap ] }, as: :json
    end
    assert_response :success
  end

  test "a viewer can't print" do
    join_as("viewer")
    post print_label_printer_path(@printer), params: { labels: [ bitmap ] }, as: :json
    assert_response :forbidden
  end

  test "print refuses labels of the wrong size, too many labels, or none" do
    post print_label_printer_path(@printer), params: { labels: [ Base64.strict_encode64("\x00" * 10) ] }, as: :json
    assert_response :unprocessable_entity
    assert_match "size", response.parsed_body["error"]

    post print_label_printer_path(@printer), params: { labels: [ "not base64!" ] }, as: :json
    assert_response :unprocessable_entity

    post print_label_printer_path(@printer), params: { labels: [ bitmap ] * 51 }, as: :json
    assert_response :unprocessable_entity

    post print_label_printer_path(@printer), params: { labels: [] }, as: :json
    assert_response :unprocessable_entity
  end

  test "an unreachable printer is reported" do
    stub_singleton(LabelPrinting::Network, :deliver, ->(*) { raise LabelPrinting::Network::Error, "Could not reach the printer." }) do
      post print_label_printer_path(@printer), params: { labels: [ bitmap ] }, as: :json
    end
    assert_response :bad_gateway
    assert_equal "Could not reach the printer.", response.parsed_body["error"]
  end

  test "settings carry the printers and the Brother media list" do
    get settings_path
    props = inertia_props
    assert_equal [ "Workshop QL" ], props["label_printers"].map { |p| p["name"] }
    assert_includes props["label_printer_media"].map { |m| m["id"] }, "62x29"
    assert props["network_printing_enabled"]
  end

  test "creating a part flashes what its label needs" do
    category = create_category(organization: @org)
    post parts_path, params: { part: { name: "Resistor 10k", category_id: category.id, ipn: "R-0001" } }
    part = Part.find_by!(name: "Resistor 10k")
    assert_equal part.id, flash[:created_part][:id]
    assert_equal part.ipn, flash[:created_part][:ipn]
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end

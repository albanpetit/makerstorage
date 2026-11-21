require "test_helper"

# Calls every route of the app against a "victim" organization (a full demo,
# with a canary string in its names) as:
#   - the owner of another organization, with the victim's ids in the path and
#     in the params: no response may show the canary, no victim row may change;
#   - a viewer of the victim organization, on every non-GET route: no victim
#     row may change.
# A new route is covered automatically. The control test checks the sweep can
# see a leak at all: the victim's own owner does see the canary.
class TenantIsolationTest < ActionDispatch::IntegrationTest
  CANARY = "CANARYZZQX"

  # Tables without organization_id, compared through their parent.
  CHILD_TABLES = {
    "loan_lines" => %w[loan_id loans], "order_lines" => %w[order_id orders],
    "part_parameters" => %w[part_id parts], "part_storages" => %w[part_id parts],
    "part_suppliers" => %w[part_id parts], "part_tags" => %w[part_id parts],
    "part_alternatives" => %w[part_id parts], "project_builds" => %w[project_id projects],
    "project_lines" => %w[project_id projects], "stocktake_lines" => %w[stocktake_id stocktakes],
    "category_parameters" => %w[category_id categories]
  }.freeze

  # Path params whose record isn't the controller's own table.
  PARAM_TABLES = {
    "attachments" => "parts", "files" => "projects", "lines" => "project_lines", "alternatives" => "parts",
    "part_attachments" => "parts", "project_files" => "projects", "members" => "organization_memberships",
    "invitations" => "organization_memberships", "duplicates" => "parts", "part_duplicates" => "parts"
  }.freeze

  # Errors a forged request may legitimately end in.
  EXPECTED_ERRORS = [
    ActiveRecord::RecordNotFound, ActionController::RoutingError, ActionController::ParameterMissing,
    ActionController::BadRequest, ActionController::UnknownFormat
  ].freeze

  setup do
    @victim_owner = create_user(email: "victim@example.com", firstname: CANARY)
    @victim = OrganizationDemo.new(@victim_owner).create!
    @victim.update!(name: "Org #{CANARY}")
    part = @victim.parts.first
    part.update!(name: "Part #{CANARY}", description: CANARY)
    part.images.attach(io: file_fixture("logo.png").open, filename: "logo.png", content_type: "image/png")
    @victim.loans.first.update!(borrower_name: "Borrower #{CANARY}")
    @victim.stocktakes.create!(user: @victim_owner, storage_location: @victim.storage_locations.first)
    @victim.label_printers.create!(name: "P #{CANARY}", protocol: "brother_ql", host: "192.168.1.50", port: 9100, media: "62x29")

    @attacker = create_user(email: "attacker@example.com")
    create_part(organization: @attacker.organizations.first, name: "Attacker part")

    @viewer = create_user(email: "viewer@example.com")
    OrganizationMembership.create!(organization: @victim, user: @viewer, role: "viewer")
  end

  test "another organization's owner can neither read nor change its data" do
    sign_in @attacker
    leaks = []
    writes = []

    each_route do |verb, path, controller|
      next if controller == "organizations" && path.include?("switch")

      url = build_path(path, controller)
      # GET routes only read: checking them for writes would double the run.
      before = victim_digest unless verb == "GET"
      call(verb, url)
      leaks << "#{verb} #{url}" if response_body.include?(CANARY)
      writes << "#{verb} #{url}" if before && victim_digest != before
    end

    post "/organizations/#{@victim.id}/switch"
    get "/"
    leaks << "switch to the victim organization" if response_body.include?(CANARY)

    assert_empty leaks, "responses showing the other organization's data"
    assert_empty writes, "requests changing the other organization's data"
  end

  test "a viewer changes nothing" do
    sign_in @viewer
    post "/organizations/#{@victim.id}/switch"
    writes = []

    each_route do |verb, path, controller|
      next if verb == "GET"
      # Their own account and memberships, not the organization's data.
      next if controller.in?(%w[profiles invitations]) || (controller == "organizations" && path.include?("switch"))

      url = build_path(path, controller)
      before = victim_digest
      call(verb, url)
      writes << "#{verb} #{url}" if victim_digest != before
      post "/organizations/#{@victim.id}/switch"
    end

    assert_empty writes, "requests a viewer could change data with"
  end

  test "control: the sweep sees the organization's own data" do
    sign_in @victim_owner
    post "/organizations/#{@victim.id}/switch"
    showing = 0

    each_route do |verb, path, controller|
      next unless verb == "GET"

      call(verb, build_path(path, controller))
      showing += 1 if response_body.include?(CANARY)
    end

    assert_operator showing, :>, 10, "the canary must show for its owner, or the sweep proves nothing"
  end

  private

  def response_body
    response&.body.to_s
  end

  def call(verb, url)
    send(verb.downcase.to_sym, url, params: verb == "GET" ? {} : body_params)
  rescue *EXPECTED_ERRORS
    nil
  end

  def each_route
    Rails.application.routes.routes.each do |route|
      verb = route.verb.to_s.split("|").first
      controller = route.defaults[:controller].to_s
      path = route.path.spec.to_s.sub("(.:format)", "")
      next if verb.blank? || controller.blank?
      next if controller.start_with?("rails/", "active_storage", "action_", "users/") || controller == "devise/sessions"

      yield verb, path, controller
    end
  end

  def build_path(path, controller)
    path.gsub(/\(([^)]*)\)/, "").gsub(/[:*](\w+)/) do
      param = Regexp.last_match(1)
      case param
      when "signed_id" then @victim.parts.first.images.first.blob.signed_id
      when "filename" then "logo.png"
      when "token" then "x"
      when "organization_id" then @victim.id
      else first_id(table_for(param, controller)) || 1
      end
    end
  end

  def table_for(param, controller)
    name = param == "id" ? controller.split("/").last : param.delete_suffix("_id")
    [ name.pluralize, name, PARAM_TABLES[name] ].compact.find { |table| first_id(table) } || "parts"
  end

  # The victim's ids under every name a controller might read them from.
  def body_params
    @body_params ||= begin
      base = { "quantity" => 1, "name" => "sweep", "ids" => victim_ids["parts"].first(3) }
      victim_ids.each do |table, ids|
        next if ids.empty?

        base["#{table.singularize}_id"] = ids.first
        base["#{table.singularize}_ids"] = ids.first(3)
      end
      zone = first_id("storage_locations")
      base.merge!("parent_id" => zone, "from_storage_location_id" => zone, "to_storage_location_id" => zone)
      nested = %w[part project project_line order order_line loan stocktake stock_movement category footprint tag supplier
                  storage_location label_printer part_supplier parameter_definition organization membership]
      nested.each_with_object(base.dup) { |key, params| params[key] = base.merge("lines" => [ base ]) }
    end
  end

  def first_id(table)
    victim_ids[table]&.first
  end

  def victim_ids
    @victim_ids ||= org_tables.to_h do |table|
      [ table, connection.select_values("SELECT id FROM #{table} WHERE organization_id = #{@victim.id} ORDER BY id") ]
    end.merge("organizations" => [ @victim.id ])
  end

  def org_tables
    connection.tables.select { |table| connection.columns(table).any? { |column| column.name == "organization_id" } }
  end

  # Every victim row (the activity log aside: reads may log, e.g. downloads).
  def victim_digest
    rows = (org_tables - %w[activity_events]).map do |table|
      [ table, connection.select_rows("SELECT * FROM #{table} WHERE organization_id = #{@victim.id} ORDER BY id") ]
    end
    rows << [ "organizations", connection.select_rows("SELECT * FROM organizations WHERE id = #{@victim.id}") ]
    CHILD_TABLES.each do |table, (key, parent)|
      rows << [ table, connection.select_rows("SELECT * FROM #{table} WHERE #{key} IN (SELECT id FROM #{parent} WHERE organization_id = #{@victim.id}) ORDER BY id") ]
    end
    Digest::SHA256.hexdigest(rows.inspect)
  end

  def connection
    ActiveRecord::Base.connection
  end
end

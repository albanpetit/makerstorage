require "test_helper"

class ActivityControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(firstname: "Ada", lastname: "Lovelace")
    @org = @owner.organizations.first
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  def add_member(role)
    user = create_user
    @org.organization_memberships.create!(user: user, role: role)
    user
  end

  test "redirects a signed-out visitor to login" do
    get activity_path
    assert_redirected_to new_user_session_path
  end

  test "members and viewers can't see the activity log" do
    %w[member viewer].each do |role|
      sign_in add_member(role)
      get activity_path
      assert_redirected_to root_path
    end
  end

  test "changes made through the app are logged and shown to admins" do
    admin = add_member("admin")
    sign_in @owner
    post tags_path, params: { tag: { name: "favorite" } }
    tag = @org.tags.find_by!(name: "favorite")
    patch tag_path(tag), params: { tag: { name: "favourite" } }

    sign_in admin
    get activity_path
    assert_response :success

    events = inertia_props["events"]
    assert_equal %w[update create], events.first(2).map { |event| event["action"] }
    assert_equal [ "Ada Lovelace", "Tag", "favourite", "/tags" ], events.first.values_at("user_name", "subject_type", "subject_label", "subject_url")
    assert_equal [ "favorite", "favourite" ], events.first["details"]["name"]
    assert_includes inertia_props["subject_types"], "Tag"
    assert_includes inertia_props["users"].map { |user| user["name"] }, "Ada Lovelace"
  end

  test "a deleted record keeps its label but loses its link" do
    sign_in @owner
    post tags_path, params: { tag: { name: "temporary" } }
    delete tag_path(@org.tags.find_by!(name: "temporary"))

    get activity_path
    events = inertia_props["events"].select { |event| event["subject_label"] == "temporary" }
    assert_equal 2, events.size
    assert events.none? { |event| event["subject_exists"] || event["subject_url"] }
  end

  test "another organization's activity never shows" do
    other = create_user
    other_org = other.organizations.first
    Current.set(user: other) { create_tag(organization: other_org, name: "Not yours") }

    sign_in @owner
    get activity_path
    assert inertia_props["events"].none? { |event| event["subject_label"] == "Not yours" }

    get activity_path, params: { user_id: other.id }
    assert_empty inertia_props["events"]
  end

  test "filters by member, record type, action and record" do
    admin = add_member("admin")
    tag = Current.set(user: @owner) { create_tag(organization: @org, name: "Mine") }
    Current.set(user: admin) { create_tag(organization: @org, name: "Theirs") }
    Current.set(user: @owner) { create_supplier(organization: @org, name: "Acme") }
    Current.set(user: @owner) { tag.update!(name: "Mine too") }
    sign_in @owner

    get activity_path, params: { user_id: admin.id }
    assert_equal [ "Theirs" ], inertia_props["events"].map { |event| event["subject_label"] }

    get activity_path, params: { subject_type: "Supplier" }
    assert_equal [ "Acme" ], inertia_props["events"].map { |event| event["subject_label"] }

    get activity_path, params: { event_action: "update" }
    assert_equal [ "Mine too" ], inertia_props["events"].map { |event| event["subject_label"] }

    get activity_path, params: { subject_type: "Tag", subject_id: tag.id }
    assert_equal %w[update create], inertia_props["events"].map { |event| event["action"] }
    assert_equal "Mine too", inertia_props["filters"]["subject_label"]

    get activity_path, params: { subject_type: "User", event_action: "drop" }
    assert_nil inertia_props["filters"]["subject_type"]
    assert_nil inertia_props["filters"]["event_action"]
  end

  test "pages through the log" do
    Current.set(user: @owner) { (ActivityController::PAGE_SIZE + 1).times { |i| create_tag(organization: @org, name: "Tag #{i}") } }
    sign_in @owner

    get activity_path, params: { page: 2 }
    assert_equal 2, inertia_props["pagination"]["page_count"]
    assert_equal [ "Tag 0" ], inertia_props["events"].map { |event| event["subject_label"] }
  end

  test "a CSV import is one event" do
    sign_in @owner
    file = Tempfile.new([ "import", ".csv" ], binmode: true)
    file.write("Name,Category\nResistor 10k,Resistors\nCapacitor,Capacitors\n")
    file.rewind

    assert_difference -> { @org.activity_events.count }, 1 do
      post import_parts_path, params: { file: Rack::Test::UploadedFile.new(file.path, "text/csv") }
    end
    event = @org.activity_events.newest_first.first
    assert_equal "import", event.action
    assert_equal({ "created" => 2, "updated" => 0, "skipped" => 0 }, event.details.slice("created", "updated", "skipped"))
  end

  test "a backup download is logged" do
    sign_in @owner

    assert_difference -> { @org.activity_events.where(action: "export").count }, 1 do
      get export_backup_path
    end
  end

  test "a role change is logged on the membership" do
    member = add_member("member")
    membership = @org.organization_memberships.find_by!(user: member)
    sign_in @owner

    patch member_path(membership), params: { member: { role: "admin" } }

    event = @org.activity_events.newest_first.first
    assert_equal [ "update", "OrganizationMembership", { "role" => %w[member admin] } ],
      [ event.action, event.subject_type, event.details ]
  end
end

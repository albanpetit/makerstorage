require "test_helper"

class ActivityEventTest < ActiveSupport::TestCase
  setup do
    @user = create_user(firstname: "Ada", lastname: "Lovelace")
    @org = @user.organizations.first
  end

  def as_user(user = @user, &block)
    Current.set(user: user, &block)
  end

  test "nothing is recorded without a signed-in user" do
    assert_no_difference -> { ActivityEvent.count } do
      part = create_part(organization: @org)
      part.update!(name: "Renamed")
      part.destroy!
    end
  end

  test "creating, updating and deleting a part are recorded with who did it" do
    resistors = create_category(organization: @org, name: "Resistors")
    capacitors = create_category(organization: @org, name: "Capacitors")
    part = as_user { create_part(organization: @org, category: resistors, name: "10k", ipn: "MS-00042") }

    created = @org.activity_events.newest_first.first
    assert_equal [ "create", "Part", part.id, "MS-00042 · 10k", @user.id, "Ada Lovelace" ],
      [ created.action, created.subject_type, created.subject_id, created.subject_label, created.user_id, created.user_name ]

    as_user { part.update!(name: "10k 1%", category: capacitors, unit_price: 0.05, rohs_compliant: true) }
    updated = @org.activity_events.newest_first.first
    assert_equal "update", updated.action
    assert_equal [ "10k", "10k 1%" ], updated.details["name"]
    assert_equal [ "Resistors", "Capacitors" ], updated.details["category"], "foreign keys are logged by label"
    assert_equal [ nil, "0.05" ], updated.details["unit_price"]
    assert_equal [ false, true ], updated.details["rohs_compliant"]
    assert_not updated.details.key?("updated_at")

    as_user { part.destroy! }
    destroyed = @org.activity_events.newest_first.first
    assert_equal [ "destroy", "MS-00042 · 10k 1%" ], [ destroyed.action, destroyed.subject_label ]
  end

  test "an update that only touches ignored attributes writes nothing" do
    project = create_project(organization: @org)

    assert_no_difference -> { ActivityEvent.count } do
      as_user { project.update!(checked_at: Time.current) }
      as_user { project.touch }
    end
  end

  test "organization secrets are logged as changed, without their values" do
    as_user { @org.update!(mouser_api_key: "secret-key", default_low_stock_threshold: 10) }

    event = @org.activity_events.newest_first.first
    assert_equal [ "update", "Organization", @org.id ], [ event.action, event.subject_type, event.subject_id ]
    assert event.details.key?("mouser_api_key")
    assert_nil event.details["mouser_api_key"]
    assert_equal [ 50, 10 ], event.details["default_low_stock_threshold"]
    assert_not_includes event.to_json, "secret-key"
  end

  test "token bookkeeping on the organization writes nothing" do
    assert_no_difference -> { ActivityEvent.count } do
      as_user { @org.update!(ipn_next_sequence: 42, digikey_access_token: "token", kicad_token_last_used_at: Time.current) }
    end
  end

  test "a new membership records its role" do
    member = create_user(firstname: "Grace", lastname: "Hopper")
    membership = as_user { @org.organization_memberships.create!(user: member, role: "admin") }

    event = @org.activity_events.newest_first.first
    assert_equal [ "create", "OrganizationMembership", membership.id, "Grace Hopper" ],
      [ event.action, event.subject_type, event.subject_id, event.subject_label ]
    assert_equal [ nil, "admin" ], event.details["role"]
  end

  test "without_recording silences the callbacks, nested blocks included" do
    assert_no_difference -> { ActivityEvent.count } do
      as_user do
        ActivityEvent.without_recording do
          ActivityEvent.without_recording { create_tag(organization: @org) }
          create_tag(organization: @org)
        end
      end
    end

    assert_difference -> { ActivityEvent.count }, 1 do
      as_user { create_tag(organization: @org) }
    end
  end

  test "a rolled-back change leaves no event" do
    assert_no_difference -> { ActivityEvent.count } do
      as_user do
        ActiveRecord::Base.transaction do
          create_tag(organization: @org)
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "long values are cut" do
    part = create_part(organization: @org)
    as_user { part.update!(description: "x" * 1000) }

    assert_operator @org.activity_events.newest_first.first.details["description"].last.length, :<=, ActivityEvent::MAX_VALUE_LENGTH
  end

  test "a deleted user's events stay, under the name they had" do
    assert_equal :nullify, User.reflect_on_association(:activity_events).options[:dependent]

    member = create_user(firstname: "Grace", lastname: "Hopper")
    as_user(member) { create_tag(organization: @org, name: "Hers") }
    event = @org.activity_events.find_by!(subject_label: "Hers")
    member.activity_events.update_all(user_id: nil)

    assert_equal "Grace Hopper", event.reload.user_name
  end

  test "deleting an organization logs nothing and takes its events" do
    org = create_organization
    org.organization_memberships.create!(user: @user, role: "owner")
    as_user { create_part(organization: org) }

    as_user { assert org.destroy }
    assert_not ActivityEvent.exists?(organization_id: org.id)
  end

  test "a reset is one event" do
    3.times { create_part(organization: @org) }

    assert_difference -> { ActivityEvent.count }, 1 do
      as_user { @org.reset_data! }
    end
    event = @org.activity_events.newest_first.first
    assert_equal [ "reset", nil, { "parts" => 3 } ], [ event.action, event.subject_type, event.details ]
  end

  test "a part merge is one event on the kept part" do
    keep = create_part(organization: @org, name: "Keep", mpn: "ABC")
    duplicate = create_part(organization: @org, name: "Dup")
    label = ActivityEvent.label_for(duplicate)

    assert_difference -> { ActivityEvent.count }, 1 do
      as_user { PartMerge.new(keep: keep, duplicates: [ duplicate ], user: @user).merge! }
    end
    event = @org.activity_events.newest_first.first
    assert_equal [ "merge", "Part", keep.id, [ label ] ], [ event.action, event.subject_type, event.subject_id, event.details["merged"] ]
  end

  test "an organization merge brings the source's history along" do
    source = create_organization(name: "Club")
    source.organization_memberships.create!(user: @user, role: "owner")
    as_user { create_tag(organization: source, name: "From the club") }

    as_user { OrganizationMerge.new(source: source, target: @org).merge! }

    assert @org.activity_events.exists?(subject_label: "From the club")
    merge = @org.activity_events.find_by!(action: "merge")
    assert_equal "Club", merge.details["organization"]
    assert_equal 2, @org.activity_events.count, "the tag's creation and the merge, nothing for the moved records"
  end

  test "record! needs a signed-in user" do
    assert_nil ActivityEvent.record!(@org, "export")
    assert_difference -> { ActivityEvent.count }, 1 do
      as_user { ActivityEvent.record!(@org, "export") }
    end
  end
end

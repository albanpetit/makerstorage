require "test_helper"

class OrganizationTemplateTest < ActiveSupport::TestCase
  setup do
    @org = create_user.organizations.first
  end

  test "makerspace creates coded categories, parameters, footprints and a zone tree" do
    result = OrganizationTemplate.apply!(@org, :makerspace)

    assert_equal "makerspace", @org.reload.onboarding_template
    assert_equal @org.categories.count, result.categories
    assert_equal "RES", @org.categories.find_by!(name: "Resistors").code
    smd = @org.categories.find_by!(name: "SMD resistors")
    assert_equal "Resistors", smd.parent.name
    assert_includes smd.parent.parameter_definitions.pluck(:name), "Resistance"
    assert @org.footprints.exists?(name: "0805", mounting_type: "SMD")

    cabinet = @org.storage_locations.find_by!(code: "A")
    assert_equal "cabinet", cabinet.location_type
    assert_equal "Electronics room", cabinet.parent.name
    assert_equal (1..6).map { |n| "Drawer A#{n}" }, cabinet.children.order(:id).pluck(:name)
    assert_equal %w[drawer], cabinet.children.distinct.pluck(:location_type)
  end

  test "templates differ in what they include" do
    OrganizationTemplate.apply!(@org, :classroom)

    assert @org.categories.exists?(name: "Breadboards and prototyping")
    assert_not @org.categories.exists?(name: "SMD resistors")
    assert_not @org.footprints.exists?(name: "0805")
    assert_equal 8, @org.storage_locations.find_by!(code: "K").children.count
    assert_equal 7, @org.reload.default_loan_days
  end

  test "names follow the current locale" do
    I18n.with_locale(:fr) { OrganizationTemplate.apply!(@org, :home_lab) }

    assert @org.categories.exists?(name: "Résistances")
    assert @org.storage_locations.exists?(name: "Tiroir C12")
    assert @org.parameter_definitions.exists?(name: "Capacitance"), "French category names still get the standard templates"
    assert @org.categories.find_by!(name: "Condensateurs").parameter_definitions.exists?(name: "Capacitance")
  end

  test "applying is additive: existing names are kept and taken codes left blank" do
    create_category(organization: @org, name: "resistors", code: "R1")
    create_category(organization: @org, name: "Other", code: "CAP")
    create_storage_location(organization: @org, name: "Workshop")
    create_storage_location(organization: @org, name: "Elsewhere", code: "C1")

    OrganizationTemplate.apply!(@org, :home_lab)

    assert_equal 1, @org.categories.where("LOWER(name) = 'resistors'").count
    assert_nil @org.categories.find_by!(name: "Capacitors").code
    assert_equal 1, @org.storage_locations.where(name: "Workshop").count
    assert_not @org.storage_locations.exists?(name: "Drawer organizer"), "a root zone that exists is skipped with its sub-zones"

    assert_no_difference -> { @org.categories.count } do
      OrganizationTemplate.apply!(@org, :home_lab)
    end
  end

  test "logs one summary event" do
    Current.user = create_user
    assert_difference -> { ActivityEvent.count }, 1 do
      OrganizationTemplate.apply!(@org, :makerspace)
    end
    event = ActivityEvent.last
    assert_equal "import", event.action
    assert_equal "makerspace", event.details["template"]
  ensure
    Current.user = nil
  end

  test "refuses an unknown template" do
    assert_raises(ArgumentError) { OrganizationTemplate.apply!(@org, :castle) }
  end
end

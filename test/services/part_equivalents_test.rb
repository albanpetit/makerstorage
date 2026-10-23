require "test_helper"

class PartEquivalentsTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @capacitance = @org.parameter_definitions.create!(name: "Capacitance", unit: "F")
    @voltage = @org.parameter_definitions.create!(name: "Voltage rating", unit: "V")
    @tolerance = @org.parameter_definitions.create!(name: "Tolerance", unit: "%")
    @dielectric = @org.parameter_definitions.create!(name: "Dielectric", value_type: "text")
    @caps = create_category(organization: @org, name: "Capacitors")
    @caps.update!(parameter_template: [ @capacitance.id, @voltage.id, @tolerance.id, @dielectric.id ])
    @c0603 = create_footprint(organization: @org, name: "0603")
    @c0805 = create_footprint(organization: @org, name: "0805")
    @zone = create_storage_location(organization: @org)
    @part = cap("100nF 25V", "100nF", "25V", "10%", "X7R")
  end

  def cap(name, capacitance, voltage = nil, tolerance = nil, dielectric = nil, footprint: @c0603, **attrs)
    part = create_part(organization: @org, category: @caps, name: name, footprint: footprint, **attrs)
    part.update!(parameter_values: { @capacitance.id => capacitance, @voltage.id => voltage.to_s,
                                     @tolerance.id => tolerance.to_s, @dielectric.id => dielectric.to_s })
    part
  end

  def suggested(part = @part)
    PartEquivalents.new(part.reload).suggestions
  end

  test "suggests parts with the same values, or better ratings and tolerances, same footprint" do
    same = cap("Same", "0.1uF", "25V", "10%", "x7r")
    better = cap("Better", "100n", "50V", "5%", "X7R")

    found = suggested.index_by { |suggestion| suggestion.part }
    assert_equal [ same, better ].to_set, found.keys.to_set
    assert_equal %w[Capacitance Dielectric Tolerance Voltage\ rating].sort, found[same].matched.sort
    assert_equal [ "Capacitance", "Dielectric" ], found[better].matched.sort
    assert_equal [ "Tolerance", "Voltage rating" ], found[better].better.sort
  end

  test "leaves out other values, lower ratings, other footprints, other categories and units, obsolete and linked parts" do
    cap("Other value", "1uF", "25V", "10%", "X7R")
    cap("Lower rating", "100nF", "16V", "10%", "X7R")
    cap("Wider tolerance", "100nF", "25V", "20%", "X7R")
    cap("Other dielectric", "100nF", "25V", "10%", "Y5V")
    cap("Bigger", "100nF", "25V", "10%", "X7R", footprint: @c0805)
    cap("Obsolete", "100nF", "25V", "10%", "X7R", status: "obsolete")
    cap("By the meter", "100nF", "25V", "10%", "X7R", unit: "meter")
    linked = cap("Linked", "100nF", "25V", "10%", "X7R")
    PartAlternative.link!(@part, linked)
    elsewhere = create_part(organization: @org, name: "Elsewhere", footprint: @c0603)
    elsewhere.update!(parameter_values: { @capacitance.id => "100nF" })

    assert_empty suggested
  end

  test "keeps a part missing a parameter, says so, and ranks it after complete ones" do
    partial = cap("Partial", "100nF", nil, nil, "X7R", footprint: nil)
    complete = cap("Complete", "100nF", "25V", "10%", "X7R")

    assert_equal [ complete, partial ], suggested.map(&:part)
    assert_equal [ "Tolerance", "Voltage rating" ], suggested.last.missing.sort
  end

  test "only loads candidates sharing a defining value" do
    cap("Other value", "1uF", "25V", "10%", "Y5V")
    same = cap("Same", "100nF", "25V", "10%", "X7R")
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/FROM "parts"/) }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal [ same ], suggested.map(&:part)
    end
    assert queries.any? { |sql| sql.include?("part_parameters") }, "candidates are filtered on their parameters in SQL"
  end

  test "a rating alone isn't enough to suggest a part" do
    cap("Only rating", "", "25V", nil, nil)
    assert_empty suggested
  end

  test "among equal matches, the part with more stock comes first" do
    low = cap("Low", "100nF", "25V", "10%", "X7R")
    high = cap("High", "100nF", "25V", "10%", "X7R")
    @org.stock_movements.create!(part: high, storage_location: @zone, movement_type: "in", quantity_delta: 50)

    assert_equal [ high, low ], suggested.map(&:part)
  end

  test "a part without parameters falls back to the same value and footprint" do
    led = create_category(organization: @org, name: "LEDs")
    red = create_part(organization: @org, category: led, name: "Red LED", value: "Red 2V", footprint: @c0603)
    twin = create_part(organization: @org, category: led, name: "Other red", value: "red 2v", footprint: @c0603)
    create_part(organization: @org, category: led, name: "Green", value: "Green", footprint: @c0603)
    create_part(organization: @org, category: led, name: "Big red", value: "Red 2V", footprint: @c0805)

    assert_equal [ twin ], suggested(red).map(&:part)
    assert_empty PartEquivalents.new(create_part(organization: @org, category: led, name: "No value")).suggestions
  end
end

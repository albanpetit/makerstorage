require "test_helper"

class PartAlternativeTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @a = create_part(organization: @org, name: "NE555P")
    @b = create_part(organization: @org, name: "LM555")
    @c = create_part(organization: @org, name: "TLC555")
  end

  test "link! stores the pair once, lower id first, and reads both ways" do
    link = PartAlternative.link!(@b, @a, note: " CMOS version ")

    assert_equal [ @a.id, @b.id ], [ link.part_id, link.alternative_part_id ]
    assert_equal "CMOS version", link.note
    assert_equal [ @b ], @a.alternative_parts.to_a
    assert_equal [ @a ], @b.alternative_parts.to_a

    assert_no_difference -> { PartAlternative.count } do
      PartAlternative.link!(@a, @b, note: "")
    end
    assert_nil link.reload.note
    assert_equal link, PartAlternative.between(@b, @a)
  end

  test "a part can't be its own alternative nor one from another organization" do
    assert_not PartAlternative.new(part: @a, alternative_part: @a).valid?

    foreign = create_part(organization: create_organization)
    link = PartAlternative.new(part: @a, alternative_part: foreign)
    assert_not link.valid?
    assert_includes link.errors.details[:alternative_part], { error: :same_organization }
  end

  test "the pair is unique whichever way it is given" do
    PartAlternative.create!(part: @a, alternative_part: @b)
    assert_not PartAlternative.new(part: @b, alternative_part: @a).valid?
  end

  test "deleting a part deletes its links from either side" do
    PartAlternative.link!(@a, @b)
    PartAlternative.link!(@c, @a)

    @a.destroy!

    assert_equal 0, PartAlternative.count
  end

  test "fold moves links onto the kept part, dropping the link between them and repeats" do
    d = create_part(organization: @org, name: "ICM7555")
    PartAlternative.link!(@a, @b)              # between the merged parts: dropped
    PartAlternative.link!(@b, @c, note: "dup") # @a already has @c: dropped
    PartAlternative.link!(@a, @c, note: "kept")
    PartAlternative.link!(@b, d, note: "moved")

    PartAlternative.fold(@b.id, @a.id)

    assert_equal [ @c, d ].sort_by(&:id), @a.alternative_parts.order(:id).to_a
    assert_equal "kept", PartAlternative.between(@a, @c).note
    assert_equal "moved", PartAlternative.between(@a, d).note
    assert_empty PartAlternative.involving(@b.id)
    assert PartAlternative.all.all? { |link| link.part_id < link.alternative_part_id }
  end
end

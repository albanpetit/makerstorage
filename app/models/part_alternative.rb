# Two parts of one organization that can stand in for each other: a second
# source, the same value from another maker, a better-rated equivalent. The
# link reads both ways, so it is stored once per pair with the lower id in
# +part_id+ (see .link!); read it through Part#alternative_links.
class PartAlternative < ApplicationRecord
  MAX_NOTE_LENGTH = 200

  belongs_to :part
  belongs_to :alternative_part, class_name: "Part"

  before_validation :order_pair
  before_validation { self.note = note.to_s.strip.presence }

  validates :alternative_part_id, uniqueness: { scope: :part_id }
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
  validate :parts_must_differ_and_share_organization

  # Every link touching any of +part_ids+, from either side.
  scope :involving, ->(part_ids) { where(part_id: part_ids).or(where(alternative_part_id: part_ids)) }

  # Links +a+ and +b+ (in any order), or returns their existing link with
  # +note+ updated when one is given. A concurrent link of the same pair
  # (double click) finds the row the other request wrote.
  def self.link!(a, b, note: nil)
    first, second = [ a, b ].sort_by(&:id)
    retried = false
    begin
      link = find_or_initialize_by(part_id: first.id, alternative_part_id: second.id)
      link.note = note unless note.nil?
      link.save!
      link
    rescue ActiveRecord::RecordNotUnique
      raise if retried

      retried = true
      retry
    end
  end

  # The link between +a+ and +b+, if any.
  def self.between(a, b)
    first, second = [ a.id, b.id ].sort
    find_by(part_id: first, alternative_part_id: second)
  end

  # Moves part +from+'s links onto part +to+ (both ids) when the two are
  # merged (PartMerge.fold): links between them and links +to+ already has
  # are dropped, the others keep their note and the lower-id-first order.
  def self.fold(from, to)
    involving(from).find_each do |link|
      other = link.other_id(from)
      if other == to || between_ids(to, other)
        link.delete
      else
        first, second = [ to, other ].sort
        link.update_columns(part_id: first, alternative_part_id: second, updated_at: Time.current)
      end
    end
  end

  def self.between_ids(a, b)
    first, second = [ a, b ].sort
    exists?(part_id: first, alternative_part_id: second)
  end

  # The part on the other side of the link from +part_id+.
  def other_id(part_id)
    self.part_id == part_id ? alternative_part_id : self.part_id
  end

  private

  def order_pair
    return unless part_id && alternative_part_id && part_id > alternative_part_id

    self.part_id, self.alternative_part_id = alternative_part_id, part_id
  end

  def parts_must_differ_and_share_organization
    return unless part && alternative_part

    errors.add(:alternative_part, :another_part) if part_id == alternative_part_id
    errors.add(:alternative_part, :same_organization) if part.organization_id != alternative_part.organization_id
  end
end

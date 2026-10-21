# Finds the parts of an organization that look like the same component entered
# twice, grouped for the duplicates page (Inventory → Duplicates).
#
#   PartDuplicates.new(organization).groups
#   # => [#<Group part_ids: [4, 9], certain: true, reasons: ["Same part number “LM358N”"]>, …]
#
# Two parts are paired when they share:
#
#   a part number   (certain) the MPN, SKU, barcode or a supplier part number of
#                   one equals any of those of the other, ignoring case, spaces
#                   and punctuation ("RC0603FR-0710KL" = "rc0603fr 0710kl")
#   name            (possible) the same name, value and footprint
#   value           (possible) the same category, value and footprint, both set
#                   ("10k" resistors in 0603 entered under two names)
#
# Pairs are chained into groups (A~B and B~C put A, B and C together). A pair
# marked "not duplicates" (PartDuplicateDismissal) is never made, so a
# dismissed group only comes back if a new part matches it.
class PartDuplicates
  Group = Data.define(:part_ids, :certain, :reasons)

  # Part numbers shorter than this (once normalized) are too generic to pair on.
  MIN_IDENTIFIER_LENGTH = 3

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^[:alnum:]]/, "")
  end

  def initialize(organization)
    @organization = organization
  end

  def groups
    @groups ||= build_groups
  end

  def count
    groups.size
  end

  private

  attr_reader :organization

  def build_groups
    parts = organization.parts.pluck(:id, :name, :mpn, :sku, :barcode, :value, :footprint_id, :category_id)
    return [] if parts.size < 2

    keys = Hash.new { |hash, key| hash[key] = { ids: Set.new, certain: false, reason: nil } }
    parts.each do |id, name, mpn, sku, barcode, value, footprint_id, category_id|
      [ mpn, sku, barcode ].each { |code| add_identifier(keys, id, code) }

      value_key = self.class.normalize(value)
      name_key = self.class.normalize(name)
      if name_key.present?
        entry = keys[[ :name, name_key, value_key, footprint_id ]]
        entry[:ids] << id
        entry[:reason] ||= I18n.t("part_duplicates.same_name")
      end
      if value_key.present? && footprint_id
        entry = keys[[ :value, category_id, value_key, footprint_id ]]
        entry[:ids] << id
        entry[:reason] ||= I18n.t("part_duplicates.same_category")
      end
    end
    PartSupplier.where(part_id: parts.map(&:first)).where.not(supplier_sku: [ nil, "" ]).pluck(:part_id, :supplier_sku)
      .each { |id, code| add_identifier(keys, id, code) }

    dismissed = PartDuplicateDismissal.where(part_id: parts.map(&:first)).pluck(:part_id, :other_part_id).to_set
    union = UnionFind.new
    edges = []
    keys.each_value do |entry|
      ids = entry[:ids].to_a.sort
      next if ids.size < 2

      ids.combination(2).each do |a, b|
        next if dismissed.include?([ a, b ]) || dismissed.include?([ b, a ])

        union.join(a, b)
        edges << [ a, entry ]
      end
    end

    reasons = Hash.new { |hash, root| hash[root] = { certain: false, reasons: [], certain_reasons: Set.new } }
    edges.each do |id, entry|
      group = reasons[union.root(id)]
      group[:certain] ||= entry[:certain]
      group[:certain_reasons] << entry[:reason] if entry[:certain]
      group[:reasons] << entry[:reason] unless group[:reasons].include?(entry[:reason])
    end

    names = parts.to_h { |id, name, *| [ id, name.to_s.downcase ] }
    union.sets.map do |root, ids|
      group = reasons[root]
      Group.new(part_ids: ids.sort, certain: group[:certain],
                reasons: group[:reasons].sort_by { |reason| group[:certain_reasons].include?(reason) ? 0 : 1 })
    end.sort_by { |group| [ group.certain ? 0 : 1, names[group.part_ids.first] ] }
  end

  def add_identifier(keys, id, code)
    normalized = self.class.normalize(code)
    return if normalized.length < MIN_IDENTIFIER_LENGTH

    entry = keys[[ :code, normalized ]]
    entry[:ids] << id
    entry[:certain] = true
    entry[:reason] ||= I18n.t("part_duplicates.same_part_number", code: code.strip)
  end

  # Disjoint sets over part ids.
  class UnionFind
    def initialize
      @parent = {}
    end

    def root(id)
      @parent[id] ||= id
      @parent[id] = root(@parent[id]) unless @parent[id] == id
      @parent[id]
    end

    def join(a, b)
      root_a = root(a)
      root_b = root(b)
      @parent[root_b] = root_a unless root_a == root_b
    end

    # root => ids, for every id seen.
    def sets
      @parent.keys.group_by { |id| root(id) }
    end
  end
end

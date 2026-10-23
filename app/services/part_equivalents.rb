# Suggests parts that could stand in for a part, from what is recorded about
# them, for the part sheet's "Alternatives" block (and MCP get_part):
#
#   PartEquivalents.new(part).suggestions # => [Suggestion, …]
#
# A candidate is another part of the same organization, in the same category
# and counted in the same unit, not obsolete, not already linked
# (PartAlternative), whose footprint is the same when both have one. It is
# then compared on the part's key parameters: the category template's
# parameters the part has a value for (all its parameters when the template
# gives none). Each one the candidate also has must match (numbers within
# RELATIVE_TOLERANCE, text ignoring case), except ratings where more is as
# good (AT_LEAST: voltage, power, current) and tolerances where less is
# (AT_MOST); a candidate missing one is kept but says so. At least one
# defining parameter (not a rating or tolerance) must match. A part with no
# parameters falls back to the same Value text and footprint.
#
# Best first: most parameters matched, fewest missing, most in stock.
class PartEquivalents
  LIMIT = 8
  RELATIVE_TOLERANCE = 0.001
  # Parameter names (lowercase) where the candidate's higher value is fine.
  AT_LEAST = [ "voltage rating", "power rating", "current rating" ].freeze
  # Parameter names (lowercase) where the candidate's lower value is fine.
  AT_MOST = [ "tolerance" ].freeze

  # +matched+ / +better+ / +missing+ list parameter names (+matched+ is
  # ["Value"] for the fallback).
  Suggestion = Data.define(:part, :matched, :better, :missing)

  def initialize(part, limit: LIMIT)
    @part = part
    @limit = limit
  end

  def suggestions
    @suggestions ||= begin
      key = key_parameters
      found = candidates.filter_map { |candidate| key.empty? ? compare_value(candidate) : compare(candidate, key) }
      found.sort_by do |suggestion|
        [ -(suggestion.matched.size + suggestion.better.size), suggestion.missing.size,
          -stock(suggestion.part), suggestion.part.name.downcase, suggestion.part.id ]
      end.first(@limit)
    end
  end

  private

  attr_reader :part

  def candidates
    linked = part.alternative_links.pluck(:part_id, :alternative_part_id).flatten
    scope = part.organization.parts
      .where(category_id: part.category_id, unit: part.unit)
      .where.not(id: [ part.id, *linked ])
      .where.not(status: "obsolete")
      .includes(:part_storages, :footprint, part_parameters: :parameter_definition)
    scope = scope.where(footprint_id: [ part.footprint_id, nil ]) if part.footprint_id
    scope
  end

  # The part's parameters to compare on (see the class comment).
  def key_parameters
    own = part.part_parameters.includes(:parameter_definition).to_a
    template = part.category.parameter_template_ids
    templated = own.select { |parameter| template.include?(parameter.parameter_definition_id) }
    templated.presence || own
  end

  def compare(candidate, key)
    values = candidate.part_parameters.index_by(&:parameter_definition_id)
    matched = []
    better = []
    missing = []
    defining = false

    key.each do |parameter|
      other = values[parameter.parameter_definition_id]
      next missing << parameter.name if other.nil?

      case verdict(parameter, other)
      when :same
        matched << parameter.name
        defining ||= !rating?(parameter)
      when :better then better << parameter.name
      else return nil
      end
    end

    Suggestion.new(part: candidate, matched: matched, better: better, missing: missing) if defining
  end

  # A part without parameters: the same Value text (ignoring case and spaces)
  # and, when it has one, the same footprint.
  def compare_value(candidate)
    value = normalized(part.value)
    return if value.nil? || normalized(candidate.value) != value
    return if part.footprint_id && candidate.footprint_id != part.footprint_id

    Suggestion.new(part: candidate, matched: [ Part.human_attribute_name(:value) ], better: [], missing: [])
  end

  # :same, :better (a rating above, a tolerance below) or :different.
  def verdict(parameter, other)
    definition = parameter.parameter_definition
    unless definition.number?
      return parameter.value.to_s.strip.casecmp?(other.value.to_s.strip) ? :same : :different
    end

    mine = parameter.numeric_value
    theirs = other.numeric_value
    return :different if mine.nil? || theirs.nil?
    return :same if (mine - theirs).abs <= RELATIVE_TOLERANCE * [ mine.abs, theirs.abs ].max

    name = definition.name.downcase
    if AT_LEAST.include?(name)
      theirs > mine ? :better : :different
    elsif AT_MOST.include?(name)
      theirs < mine ? :better : :different
    else
      :different
    end
  end

  def rating?(parameter)
    name = parameter.parameter_definition.name.downcase
    AT_LEAST.include?(name) || AT_MOST.include?(name)
  end

  def normalized(text)
    text.to_s.gsub(/\s+/, "").downcase.presence
  end

  def stock(candidate)
    candidate.part_storages.sum(&:quantity)
  end
end

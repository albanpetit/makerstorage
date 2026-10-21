# frozen_string_literal: true

# Reads and writes the values of number parameters (ParameterDefinition) the
# way electronics people type them, in the definition's unit:
#
#   ParameterValue.parse("4k7", "Ω")      # => 4700.0
#   ParameterValue.parse("100nF", "F")    # => 1.0e-07
#   ParameterValue.parse("1/4 W", "W")    # => 0.25
#   ParameterValue.parse("±5 %", "%")     # => 5.0
#   ParameterValue.parse("3V3", "V")      # => 3.3
#   ParameterValue.format(4700.0, "Ω")    # => "4.7 kΩ"
#
# Accepted: SI prefixes (p n µ/u m k M G T, "meg"), a prefix or "R" (or the
# unit's own letter) in place of the decimal point ("4k7", "4R7", "2u2",
# "3V3"), fractions ("1/4"), a decimal comma, exponents ("1e-6"), a leading
# "±", and the unit or one of its spellings at the end ("10 ohm", "10R",
# "16MHz"). Anything else doesn't parse (nil): it isn't a number in that unit.
module ParameterValue
  PREFIXES = {
    "p" => 1e-12, "n" => 1e-9, "u" => 1e-6, "μ" => 1e-6, "m" => 1e-3,
    "k" => 1e3, "K" => 1e3, "M" => 1e6, "meg" => 1e6, "G" => 1e9, "T" => 1e12
  }.freeze

  # The prefixes #format writes, by power of ten.
  FORMAT_PREFIXES = { -12 => "p", -9 => "n", -6 => "µ", -3 => "m", 0 => "", 3 => "k", 6 => "M", 9 => "G", 12 => "T" }.freeze

  # Units #format scales with a prefix ("4.7 kΩ", "100 nF"). Others (%, °C,
  # ppm, mm, plain counts…) are written as stored.
  SI_UNITS = %w[Ω F H V W A Hz s J Wh Ah lm cd T Pa g].freeze

  # Other spellings of a unit accepted at the end of a value (compared without
  # case, after Unicode normalization: "Ω" ohm sign → "Ω", "µ" micro → "μ").
  UNIT_ALIASES = {
    "Ω" => %w[ohms ohm r],
    "°C" => %w[ºc degc c],
    "Hz" => %w[hz]
  }.freeze

  NUMBER = /[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/i
  PREFIX = /meg|[pnuμmkKMGT]/

  module_function

  # The value of +text+ in +unit+ (a Float), or nil when it isn't one.
  def parse(text, unit = nil)
    string = normalize(text)
    return nil if string.empty?

    string = strip_unit(string, unit)
    value = parse_infix(string, unit) || parse_fraction(string) || parse_number(string)
    # Twelve significant digits: "100n" is 1.0e-07, not 1.0000000000000001e-07.
    Float(Kernel.format("%.12g", value)) if value&.finite?
  end

  # +value+ (in +unit+) for display: scaled with an SI prefix for SI units,
  # four significant digits at most.
  def format(value, unit = nil)
    return nil if value.nil?

    unit = unit.to_s
    number, prefix = SI_UNITS.include?(unit) ? scale(value) : [ value, "" ]
    text = number_text(number)
    return "#{text}#{prefix}" if unit.empty?

    "#{text}#{unit == '%' ? '' : ' '}#{prefix}#{unit}"
  end

  # -- Parsing ----------------------------------------------------------------

  def normalize(text)
    string = text.to_s.unicode_normalize(:nfkc).strip
    string = string.delete_prefix("±").delete_prefix("+/-").delete_prefix("+-")
    string = string.gsub(/\s+/, "")
    string = string.tr(",", ".") unless string.include?(".")
    string
  end

  # Drops the unit (or one of its spellings) from the end of +string+, when
  # something is left before it.
  def strip_unit(string, unit)
    spellings(unit).sort_by { |spelling| -spelling.length }.each do |spelling|
      next unless string.length > spelling.length && string.downcase.end_with?(spelling)

      return string[0...-spelling.length]
    end
    string
  end

  def spellings(unit)
    return [] if unit.blank?

    unit = unit.unicode_normalize(:nfkc)
    [ unit.downcase, *UNIT_ALIASES.fetch(unit, []) ].uniq
  end

  # "4k7" (4.7k), "4R7" (4.7), "3V3" (3.3 V): a prefix, "R", or the unit's own
  # one-letter spelling between the integer and the decimals.
  def parse_infix(string, unit)
    match = string.match(/\A(\d+)(meg|[a-zμ])(\d+)\z/i)
    return nil unless match

    marker = match[2]
    letters = spellings(unit).select { |spelling| spelling.length == 1 }
    multiplier = PREFIXES[marker] || (1.0 if marker.casecmp?("r") || letters.include?(marker.downcase))
    return nil unless multiplier

    Float("#{match[1]}.#{match[3]}") * multiplier
  end

  def parse_fraction(string)
    match = string.match(/\A(\d+)\/(\d+)(#{PREFIX})?\z/)
    return nil unless match && match[2].to_i.positive?

    match[1].to_f / match[2].to_i * PREFIXES.fetch(match[3], 1.0)
  end

  def parse_number(string)
    match = string.match(/\A(#{NUMBER})(#{PREFIX})?\z/)
    return nil unless match

    Float(match[1]) * PREFIXES.fetch(match[2], 1.0)
  rescue ArgumentError
    nil
  end

  # -- Formatting -------------------------------------------------------------

  def scale(value)
    return [ 0.0, "" ] if value.zero?

    exponent = ((Math.log10(value.abs) / 3).floor * 3).clamp(-12, 12)
    number = significant(value / (10.0**exponent))
    if number.abs >= 1000 && exponent < 12
      exponent += 3
      number = significant(number / 1000)
    end
    [ number, FORMAT_PREFIXES.fetch(exponent) ]
  end

  def significant(number)
    Float(Kernel.format("%.4g", number))
  end

  def number_text(number)
    rounded = significant(number)
    return rounded.to_i.to_s if rounded == rounded.round && rounded.abs < 1e15

    text = Kernel.format("%.4g", rounded)
    text.include?("e") ? rounded.to_s : text
  end
end

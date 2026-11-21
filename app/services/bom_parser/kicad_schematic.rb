# frozen_string_literal: true

require "strscan"

module BomParser
  # Reads the bill of materials straight out of KiCad schematics (.kicad_sch,
  # KiCad 6 and later), so a project's KiCad files fill its BOM without a
  # separate export:
  #
  #   lines = BomParser::KicadSchematic.parse([ [ "board.kicad_sch", text ], … ])
  #
  # Every placed symbol of every sheet counts once per reference: multi-unit
  # symbols (U1A, U1B) are one part, and a sub-sheet placed twice lists both
  # sets of references in its symbols' instance data. Power symbols ("#…"),
  # symbols left out of the BOM and DNP symbols are skipped. The result has the
  # same shape and grouping as the other KiCad formats (BomParser::Kicad.group).
  module KicadSchematic
    # The text isn't a KiCad 6+ schematic (KiCad 5 ".sch" files, or junk).
    class NotASchematic < StandardError; end
    # The sheets hold more than MAX_TOKENS_PER_SHEET / MAX_KEPT_TOKENS: far
    # beyond any real schematic, and reading them would take too much memory.
    class TooLarge < StandardError; end

    # A real sheet runs about 5 bytes a token, so 2 million tokens is a 10 MB
    # sheet; the symbols the BOM keeps are a small part of that.
    MAX_TOKENS_PER_SHEET = 2_000_000
    MAX_KEPT_TOKENS = 1_000_000

    module_function

    # The only top-level lists the BOM needs. Everything else (library symbol
    # drawings, wires, labels, graphics: most of a sheet) is dropped as soon as
    # it is read, so a sheet's tree stays a fraction of its text's size.
    BOM_NODES = %w[symbol symbol_instances].freeze

    # +sources+ is a list of [filename, text] pairs, one per sheet.
    def parse(sources)
      kept = { left: MAX_KEPT_TOKENS }
      sheets = sources.map do |name, text|
        root = begin
          SExpression.parse(text, keep: BOM_NODES, max_tokens: MAX_TOKENS_PER_SHEET, kept: kept)
        rescue TooLarge
          raise TooLarge, name
        end
        raise NotASchematic, name unless root.is_a?(Array) && root.first == "kicad_sch"

        [ name, root ]
      end

      project_name = project_name(sheets)
      # KiCad 6 keeps every symbol's references in the root sheet, keyed by the
      # path that ends in the symbol's uuid.
      legacy_references = sheets.flat_map { |_, root| children(root, "symbol_instances") }
        .flat_map { |list| children(list, "path") }
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, refs|
          reference = value(path, "reference")
          refs[path[1].to_s.split("/").last] << reference if reference
        end

      seen = Set.new
      components = []
      sheets.each do |_, root|
        children(root, "symbol").each do |symbol|
          next unless value(symbol, "lib_id")
          next if value(symbol, "in_bom") == "no" || value(symbol, "dnp") == "yes"

          properties = children(symbol, "property").to_h { |p| [ Kicad.symbolize(p[1]), p[2].to_s.strip ] }
          next if Kicad.dnp?(Kicad.field(properties, :dnp))

          references = instance_references(symbol, project_name).presence ||
            legacy_references[value(symbol, "uuid")].presence ||
            [ properties[:reference] ].compact
          references.each do |reference|
            next if reference.start_with?("#")
            # Unannotated symbols ("R?") are each their own part.
            key = reference.include?("?") ? [ reference, value(symbol, "uuid") ] : reference
            next unless seen.add?(key)

            components << {
              designators: [ reference ],
              value: properties[:value].presence,
              footprint: properties[:footprint].presence,
              mpn: Kicad.field(properties, :mpn),
              sku: Kicad.field(properties, :sku),
              description: Kicad.field(properties, :description),
              quantity: 1
            }
          end
        end
      end

      Kicad.group(components.sort_by { |c| natural_key(c[:designators].first) })
    end

    # "R2" before "R10".
    def natural_key(reference)
      reference.scan(/\d+|\D+/).map { |chunk| chunk.match?(/\A\d/) ? [ 1, chunk.to_i ] : [ 0, chunk ] }
    end

    # KiCad 7+ lists a symbol's reference once per sheet instance, under the
    # project(s) using the sheet. A sheet shared with another project carries
    # that project's references too, so only this project's count when the
    # name is known.
    def instance_references(symbol, project_name)
      projects = children(symbol, "instances").flat_map { |instances| children(instances, "project") }
      chosen = projects.select { |project| project[1] == project_name }.presence || projects.first(1)
      chosen.flat_map { |project| children(project, "path") }.filter_map { |path| value(path, "reference") }
    end

    # The project the files belong to: the sheet whose name every
    # <name>.kicad_sch root shares with its .kicad_pro. Sub-sheets carry the
    # root project's name in their instance data, so the root's name wins.
    def project_name(sheets)
      names = sheets.map { |name, _| File.basename(name.to_s, ".kicad_sch") }
      used = sheets.flat_map { |_, root| children(root, "symbol") }
        .flat_map { |symbol| children(symbol, "instances") }
        .flat_map { |instances| children(instances, "project") }
        .map { |project| project[1] }
      (names & used).first || used.first
    end

    def children(node, name)
      node.select { |child| child.is_a?(Array) && child.first == name }
    end

    # The first atom of +node+'s first +name+ child: (in_bom yes) -> "yes".
    def value(node, name)
      child = node.find { |c| c.is_a?(Array) && c.first == name }
      child && child[1].is_a?(String) ? child[1] : nil
    end

    # A minimal S-expression reader for KiCad's file format: lists become
    # arrays, atoms and quoted strings become strings. With +keep+, only the
    # root's child lists headed by one of those names are kept. Raises TooLarge
    # past +max_tokens+ tokens read, or once the kept lists hold more tokens
    # than +kept+[:left] (a budget shared by the sheets of one BOM).
    module SExpression
      TOKEN = /\s*(?:(\()|(\))|"((?:[^"\\]|\\.)*)"|([^\s()"]+))/m
      ESCAPES = { "n" => "\n", "t" => "\t", "r" => "\r" }.freeze

      module_function

      def parse(text, keep: nil, max_tokens: nil, kept: nil)
        scanner = StringScanner.new(text)
        stack = [ [] ]
        tokens = 0
        child_start = 0
        until scanner.eos?
          break unless scanner.scan(TOKEN)

          tokens += 1
          raise TooLarge if max_tokens && tokens > max_tokens

          if scanner[1]
            child_start = tokens if stack.size == 2
            stack.push([])
          elsif scanner[2]
            raise NotASchematic, "unbalanced parentheses" if stack.size < 2

            list = stack.pop
            # stack.size == 2: +list+ is a direct child of the root list.
            if keep && stack.size == 2
              next unless keep.include?(list.first)

              if kept
                kept[:left] -= tokens - child_start
                raise TooLarge if kept[:left].negative?
              end
            end

            stack.last << list
          elsif scanner[3]
            stack.last << scanner[3].gsub(/\\(.)/m) { ESCAPES.fetch(::Regexp.last_match(1), ::Regexp.last_match(1)) }
          else
            stack.last << scanner[4]
          end
        end
        raise NotASchematic, "unbalanced parentheses" unless stack.size == 1 && scanner.rest.strip.empty?

        stack.first.first
      end
    end
  end
end

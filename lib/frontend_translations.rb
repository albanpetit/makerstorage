# The React UI's translations (app/frontend/lib/i18n.ts) are keyed by their
# English text: the string passed to t()/tx(), or the plural form passed second
# to tn()/txn(). This reads those keys from the frontend sources so a test and
# `bin/rails i18n:frontend` can tell which ones a locale file lacks.
module FrontendTranslations
  SOURCES = "app/frontend/**/*.{ts,tsx}"
  # The helpers' own file only mentions them in comments.
  SKIPPED = %w[app/frontend/lib/i18n.ts].freeze
  LITERAL = /'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/
  CALL = /(?<![\w.])(tn|txn|t|tx)\(\s*(#{LITERAL})(?:\s*,\s*(#{LITERAL}))?/m

  module_function

  # { "English text" => ["app/frontend/…:12", …] }
  def used_keys(root = Rails.root)
    keys = Hash.new { |hash, key| hash[key] = [] }
    Dir.glob(root.join(SOURCES)).sort.each do |path|
      relative = Pathname(path).relative_path_from(root).to_s
      next if SKIPPED.include?(relative)

      source = File.read(path)
      source.to_enum(:scan, CALL).each do
        match = Regexp.last_match
        plural = match[1].start_with?("tn", "txn")
        next if plural && match[3].nil?

        line = source[0...match.begin(0)].count("\n") + 1
        keys[unquote(plural ? match[3] : match[2])] << "#{relative}:#{line}"
      end
    end
    keys
  end

  def catalog(locale, root = Rails.root)
    JSON.parse(File.read(root.join("app/frontend/locales/#{locale}.json")))
  end

  def missing_keys(locale, root = Rails.root)
    used_keys(root).keys - catalog(locale, root).keys
  end

  def unused_keys(locale, root = Rails.root)
    catalog(locale, root).keys - used_keys(root).keys
  end

  def unquote(literal)
    literal[1...-1].gsub(/\\(.)/) { ::Regexp.last_match(1) == "n" ? "\n" : ::Regexp.last_match(1) }
  end
end

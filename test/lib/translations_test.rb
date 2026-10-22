require "test_helper"

class TranslationsTest < ActiveSupport::TestCase
  LOCALE_FILES = Rails.root.glob("config/locales/app.*.yml")

  test "the French catalog of the React UI covers every text it uses" do
    missing = FrontendTranslations.missing_keys(:fr)
    used = FrontendTranslations.used_keys
    assert_empty missing, "Missing from app/frontend/locales/fr.json (run bin/rails i18n:frontend):\n" +
      missing.map { |key| "  #{key.inspect}  # #{used[key].first}" }.join("\n")
  end

  test "the French catalog of the React UI has no leftover texts" do
    assert_empty FrontendTranslations.unused_keys(:fr)
  end

  test "French texts of the React UI keep the English placeholders" do
    FrontendTranslations.catalog(:fr).each do |english, french|
      # The singular may spell the count out ("Le composant…" for one).
      expected = french.is_a?(Hash) ? placeholders(english) - %w[count] : placeholders(english)
      Array(french.is_a?(Hash) ? french.values : french).each do |text|
        actual = french.is_a?(Hash) ? placeholders(text) - %w[count] : placeholders(text)
        assert_equal expected, actual, "#{english.inspect} → #{text.inspect}"
      end
    end
  end

  test "the server's English and French files define the same keys" do
    en = flatten(YAML.load_file(Rails.root.join("config/locales/app.en.yml"))["en"])
    # Attribute names default to their humanized column name in English.
    fr = flatten(YAML.load_file(Rails.root.join("config/locales/app.fr.yml"))["fr"]).reject { |key, _| key.start_with?("attributes.") }

    assert_equal en.keys.sort, fr.keys.sort
    en.each do |key, text|
      assert_equal placeholders(text), placeholders(fr[key]), "fr.#{key} doesn't use the same placeholders as en.#{key}"
    end
    assert_equal 2, LOCALE_FILES.size
  end

  test "French is available next to English, which stays the default" do
    assert_equal %i[en fr], I18n.available_locales
    assert_equal :en, I18n.default_locale
    I18n.with_locale(:fr) { assert_equal "Composant mis à jour.", I18n.t("flash.parts.part_updated_successfully") }
  end

  private

  def placeholders(text)
    text.to_s.scan(/%?\{(\w+)\}/).flatten.sort.uniq
  end

  def flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), flat|
      path = [ prefix, key ].compact.join(".")
      # A plural ({one, other}) is one entry.
      if value.is_a?(Hash) && !(value.keys - %w[one other zero]).empty?
        flat.merge!(flatten(value, path))
      else
        flat[path] = value.is_a?(Hash) ? value.values.join(" ") : value
      end
    end
  end
end

namespace :i18n do
  desc "List the React UI's texts missing from (or unused in) app/frontend/locales/fr.json"
  task frontend: :environment do
    missing = FrontendTranslations.missing_keys(:fr)
    unused = FrontendTranslations.unused_keys(:fr)
    used = FrontendTranslations.used_keys

    puts "Missing from fr.json (#{missing.size}):" if missing.any?
    missing.each { |key| puts "  #{key.inspect}  # #{used[key].first}" }
    puts "Unused in fr.json (#{unused.size}):" if unused.any?
    unused.each { |key| puts "  #{key.inspect}" }
    puts "fr.json covers every text of the React UI." if missing.empty? && unused.empty?
  end
end

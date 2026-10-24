# Starting points for a new organization (guided onboarding on the dashboard):
# a category tree with codes, the standard parameters templated onto it,
# common footprints and a storage-zone tree, for a makerspace, a home workshop
# or a classroom.
#
# Names are written in the current locale (English or French): they're the
# organization's own data from then on, renamed like anything typed by hand.
# Applying is additive, so it never clashes with what's already there:
# categories and footprints that exist by name are kept, a root zone that
# exists by name is skipped with its sub-zones, and a code already taken is
# left blank.
class OrganizationTemplate
  KEYS = %w[makerspace home_lab classroom].freeze
  ALL = KEYS.map(&:to_sym).freeze

  # { code:, en:, fr:, color:, only: [templates] (default: all), children: [] }
  CATEGORIES = [
    { code: "RES", en: "Resistors", fr: "Résistances", color: "#ef4444", children: [
      { code: "RSMD", en: "SMD resistors", fr: "Résistances CMS", only: %i[makerspace home_lab] },
      { code: "RTH", en: "Through-hole resistors", fr: "Résistances traversantes", only: %i[makerspace home_lab] },
      { code: "POT", en: "Potentiometers", fr: "Potentiomètres" }
    ] },
    { code: "CAP", en: "Capacitors", fr: "Condensateurs", color: "#f97316", children: [
      { code: "CCER", en: "Ceramic capacitors", fr: "Condensateurs céramiques", only: %i[makerspace home_lab] },
      { code: "CELE", en: "Electrolytic capacitors", fr: "Condensateurs électrolytiques", only: %i[makerspace home_lab] },
      { code: "CFILM", en: "Film capacitors", fr: "Condensateurs film", only: %i[makerspace] }
    ] },
    { code: "IND", en: "Inductors", fr: "Bobines et inductances", color: "#eab308", only: %i[makerspace] },
    { code: "DIO", en: "Diodes", fr: "Diodes", color: "#84cc16" },
    { code: "TRA", en: "Transistors", fr: "Transistors", color: "#22c55e" },
    { code: "IC", en: "Integrated circuits", fr: "Circuits intégrés", color: "#14b8a6", children: [
      { code: "MCU", en: "Microcontrollers", fr: "Microcontrôleurs", only: %i[makerspace home_lab] },
      { code: "REG", en: "Voltage regulators", fr: "Régulateurs de tension", only: %i[makerspace home_lab] }
    ] },
    { code: "XTL", en: "Crystals and oscillators", fr: "Quartz et oscillateurs", color: "#06b6d4", only: %i[makerspace] },
    { code: "OPTO", en: "Optoelectronics", fr: "Optoélectronique", color: "#ec4899", children: [
      { code: "LED", en: "LEDs", fr: "LEDs" },
      { code: "DISP", en: "Displays", fr: "Afficheurs" }
    ] },
    { code: "CON", en: "Connectors", fr: "Connecteurs", color: "#3b82f6" },
    { code: "SW", en: "Switches and relays", fr: "Interrupteurs et relais", color: "#8b5cf6" },
    { code: "SEN", en: "Sensors", fr: "Capteurs", color: "#a855f7" },
    { code: "MOD", en: "Modules and dev boards", fr: "Modules et cartes de développement", color: "#6366f1" },
    { code: "MOT", en: "Motors and actuators", fr: "Moteurs et actionneurs", color: "#0ea5e9", only: %i[makerspace classroom] },
    { code: "PWR", en: "Power and batteries", fr: "Alimentations et batteries", color: "#f59e0b", only: %i[makerspace classroom] },
    { code: "PROTO", en: "Breadboards and prototyping", fr: "Plaques d’essai et prototypage", color: "#10b981", only: %i[classroom home_lab] },
    { code: "WIR", en: "Wire and cables", fr: "Fils et câbles", color: "#64748b" },
    { code: "HW", en: "Hardware", fr: "Visserie et quincaillerie", color: "#78716c", only: %i[makerspace home_lab] },
    { code: "TOOL", en: "Tools", fr: "Outillage", color: "#0f766e", only: %i[makerspace classroom] },
    { code: "CONS", en: "Consumables", fr: "Consommables", color: "#6b7280" }
  ].freeze

  # [name, mounting type, templates (default: all)]
  FOOTPRINTS = [
    [ "0402", "SMD", %i[makerspace] ], [ "0603", "SMD", %i[makerspace home_lab] ],
    [ "0805", "SMD", %i[makerspace home_lab] ], [ "1206", "SMD", %i[makerspace home_lab] ],
    [ "SOT-23", "SMD", %i[makerspace home_lab] ], [ "SOT-223", "SMD", %i[makerspace] ],
    [ "SOIC-8", "SMD", %i[makerspace home_lab] ], [ "TQFP-32", "SMD", %i[makerspace] ],
    [ "QFN-32", "SMD", %i[makerspace] ],
    [ "Axial", "Through-hole" ], [ "Radial", "Through-hole" ], [ "DIP-8", "Through-hole" ],
    [ "DIP-16", "Through-hole" ], [ "TO-92", "Through-hole" ], [ "TO-220", "Through-hole" ],
    [ "5 mm LED", "Through-hole" ]
  ].freeze

  # One tree per template: { code:, en:, fr:, type:, children: [] }.
  # `drawers:`/`boxes:` add numbered children ("Drawer A1", code "A1"…).
  ZONES = {
    makerspace: [
      { code: "ELEC", en: "Electronics room", fr: "Salle électronique", type: "room", children: [
        { code: "A", en: "Component cabinet", fr: "Armoire à composants", type: "cabinet", numbered: [ "drawer", 6 ] },
        { code: "B", en: "Box shelf", fr: "Étagère des boîtes", type: "shelf", numbered: [ "box", 4 ] },
        { code: "BENCH", en: "Soldering bench", fr: "Poste de soudure", type: "bench" },
        { code: "TOOLS", en: "Tool shelf", fr: "Étagère outillage", type: "shelf" }
      ] },
      { code: "SORT", en: "To sort", fr: "À trier", type: "box" }
    ],
    home_lab: [
      { code: "WS", en: "Workshop", fr: "Atelier", type: "room", children: [
        { code: "BENCH", en: "Workbench", fr: "Établi", type: "bench" },
        { code: "C", en: "Drawer organizer", fr: "Casier à tiroirs", type: "cabinet", numbered: [ "drawer", 12 ] },
        { code: "S", en: "Storage shelf", fr: "Étagère de rangement", type: "shelf", numbered: [ "box", 3 ] }
      ] }
    ],
    classroom: [
      { code: "LAB", en: "Lab room", fr: "Salle de TP", type: "room", children: [
        { code: "T", en: "Teacher cabinet", fr: "Armoire enseignant", type: "cabinet", numbered: [ "shelf", 3 ] },
        { code: "K", en: "Student kits", fr: "Bacs élèves", type: "shelf", numbered: [ "box", 8 ] },
        { code: "CONS", en: "Consumables", fr: "Consommables", type: "drawer" },
        { code: "LOAN", en: "Lending shelf", fr: "Étagère des prêts", type: "shelf" }
      ] }
    ]
  }.freeze

  NUMBERED_NAMES = {
    "drawer" => { en: "Drawer", fr: "Tiroir" },
    "box" => { en: "Box", fr: "Boîte" },
    "shelf" => { en: "Shelf", fr: "Étagère" }
  }.freeze

  # Settings a template changes from the defaults: a class lends for a week.
  SETTINGS = { classroom: { default_loan_days: 7 } }.freeze

  Result = Data.define(:categories, :footprints, :storage_locations, :parameters)

  def self.apply!(organization, key, log: true)
    new(organization, key).apply!(log: log)
  end

  attr_reader :organization, :key

  def initialize(organization, key)
    raise ArgumentError, "unknown template #{key.inspect}" unless KEYS.include?(key.to_s)

    @organization = organization
    @key = key.to_sym
    @language = I18n.locale.to_s.start_with?("fr") ? :fr : :en
  end

  # Creates what's missing, records the template on the organization and logs
  # one summary event instead of one per record (unless +log+ is false).
  # Returns counts of what was added.
  def apply!(log: true)
    organization.transaction do
      counts = ActivityEvent.without_recording do
        categories = add_categories(CATEGORIES, nil)
        footprints = add_footprints
        zones = add_zones(ZONES.fetch(key), nil)
        parameters = ParameterDefinition.install_standard!(organization)[:added]
        organization.update!(SETTINGS.fetch(key, {}).merge(onboarding_template: key.to_s))
        Result.new(categories: categories, footprints: footprints, storage_locations: zones, parameters: parameters)
      end

      if log
        ActivityEvent.record!(organization, "import", details: { "template" => key.to_s }.merge(counts.to_h.transform_keys(&:to_s)))
      end
      counts
    end
  end

  private

  def name_of(entry)
    entry.fetch(@language)
  end

  def included?(entry)
    entry.fetch(:only, ALL).include?(key)
  end

  def add_categories(entries, parent)
    entries.select { |entry| included?(entry) }.sum do |entry|
      name = name_of(entry)
      category = organization.categories.find_by("LOWER(name) = ?", name.downcase)
      added = 0
      unless category
        category = organization.categories.create!(name: name, parent: parent, color: entry[:color],
                                                   code: free_category_code(entry[:code]))
        added = 1
      end
      added + add_categories(entry.fetch(:children, []), category)
    end
  end

  def free_category_code(code)
    code unless organization.categories.exists?([ "LOWER(code) = ?", code.downcase ])
  end

  def add_footprints
    FOOTPRINTS.count do |name, mounting_type, only|
      next false unless (only || ALL).include?(key)
      next false if organization.footprints.exists?([ "LOWER(name) = ?", name.downcase ])

      organization.footprints.create!(name: name, mounting_type: mounting_type)
    end
  end

  def add_zones(entries, parent)
    entries.sum do |entry|
      name = name_of(entry)
      siblings = parent ? parent.children : organization.storage_locations.root_locations
      next 0 if siblings.exists?([ "LOWER(name) = ?", name.downcase ])

      zone = create_zone(name, entry[:type], entry[:code], parent)
      numbered = entry[:numbered] ? add_numbered(zone, *entry[:numbered], entry[:code]) : 0
      1 + numbered + add_zones(entry.fetch(:children, []), zone)
    end
  end

  # "Drawer A1" … "Drawer A6" inside cabinet A.
  def add_numbered(parent, type, count, prefix)
    label = NUMBERED_NAMES.fetch(type).fetch(@language)
    (1..count).each { |number| create_zone("#{label} #{prefix}#{number}", type, "#{prefix}#{number}", parent) }
    count
  end

  def create_zone(name, type, code, parent)
    code = nil if organization.storage_locations.exists?([ "LOWER(code) = ?", code.downcase ])
    organization.storage_locations.create!(name: name, location_type: type, code: code, parent: parent)
  end
end

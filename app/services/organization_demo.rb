# A throwaway organization filled with a small makerspace's stock, to look
# around before entering anything real: the makerspace template
# (OrganizationTemplate), about twenty parts in its zones with supplier links
# and price breaks, a month of movements, a received, a shipped and a late
# order, two projects (one short of parts), and two loans (one overdue).
#
# The user gets it as owner and deletes it in one click from the banner the
# layout shows on a demo (`organizations.demo`). One demo per user: asking
# again opens the one they already have. Names follow the current locale, like
# the template's. Nothing is written to the activity log.
class OrganizationDemo
  # [key, en, fr, category code, footprint, value, mpn, manufacturer, unit price,
  #  min stock, zone code, received, used, supplier, unit]
  PARTS = [
    [ :r10k, "10 kΩ resistor 0805", "Résistance 10 kΩ 0805", "RSMD", "0805", "10k", "RC0805FR-0710KL", "Yageo", 0.01, 100, "B1", 500, 120, "lcsc" ],
    [ :r1k, "1 kΩ resistor 0805", "Résistance 1 kΩ 0805", "RSMD", "0805", "1k", "RC0805FR-071KL", "Yageo", 0.01, 100, "B1", 500, 180, "lcsc" ],
    [ :r220, "220 Ω resistor 1/4 W", "Résistance 220 Ω 1/4 W", "RTH", "Axial", "220", "CFR-25JB-52-220R", "Yageo", 0.03, 50, "B2", 200, 170, "mouser" ],
    [ :c100n, "100 nF ceramic capacitor 0805", "Condensateur céramique 100 nF 0805", "CCER", "0805", "100nF", "CL21B104KBCNNNC", "Samsung", 0.02, 100, "B3", 500, 60, "lcsc" ],
    [ :c10u, "10 µF electrolytic capacitor", "Condensateur électrolytique 10 µF", "CELE", "Radial", "10uF", "EEU-FC1H100", "Panasonic", 0.12, 30, "B3", 100, 40, "mouser" ],
    [ :d4148, "1N4148 signal diode", "Diode de signal 1N4148", "DIO", "Axial", "1N4148", "1N4148", "onsemi", 0.03, 50, "B4", 200, 30, "mouser" ],
    [ :q2222, "PN2222A NPN transistor", "Transistor NPN PN2222A", "TRA", "TO-92", "PN2222A", "PN2222ABU", "onsemi", 0.18, 20, "B4", 100, 25, "mouser" ],
    [ :atmega, "ATmega328P microcontroller", "Microcontrôleur ATmega328P", "MCU", nil, "ATmega328P", "ATMEGA328P-PU", "Microchip", 2.6, 5, "A1", 20, 16, "digikey" ],
    [ :ams1117, "AMS1117 3.3 V regulator", "Régulateur 3,3 V AMS1117", "REG", "SOT-223", "3.3V", "AMS1117-3.3", "Advanced Monolithic Systems", 0.15, 10, "A1", 50, 12, "lcsc" ],
    [ :esp32, "ESP32 DevKitC board", "Carte ESP32 DevKitC", "MOD", nil, nil, "ESP32-DEVKITC-32E", "Espressif", 9.5, 5, "A2", 10, 10, "mouser" ],
    [ :uno, "Arduino Uno R3", "Arduino Uno R3", "MOD", nil, nil, "A000066", "Arduino", 24.0, 4, "A2", 12, 3, "mouser" ],
    [ :led_red, "Red LED 5 mm", "LED rouge 5 mm", "LED", "5 mm LED", "Red", "WP7113ID", "Kingbright", 0.08, 50, "A3", 300, 90, "mouser" ],
    [ :led_green, "Green LED 5 mm", "LED verte 5 mm", "LED", "5 mm LED", "Green", "WP7113GD", "Kingbright", 0.09, 50, "A3", 300, 40, "mouser" ],
    [ :hcsr04, "HC-SR04 ultrasonic sensor", "Capteur à ultrasons HC-SR04", "SEN", nil, nil, "HC-SR04", nil, 2.5, 5, "A4", 15, 6, nil ],
    [ :bme280, "BME280 sensor module", "Module capteur BME280", "SEN", nil, nil, "BME280-MODULE", nil, 6.5, 5, "A4", 10, 7, nil ],
    [ :lcd, "16x2 LCD display", "Afficheur LCD 16x2", "DISP", nil, nil, "LCD1602-I2C", nil, 4.2, 3, "A5", 8, 2, nil ],
    [ :servo, "SG90 micro servo", "Micro servomoteur SG90", "MOT", nil, nil, "SG90", "TowerPro", 2.1, 5, "A5", 10, 4, nil ],
    [ :headers, "Pin headers 2.54 mm 1x40", "Barrettes mâles 2,54 mm 1x40", "CON", nil, nil, "PH-1X40-254", nil, 0.25, 20, "A6", 100, 35, "lcsc" ],
    [ :solder, "Lead-free solder wire 0.8 mm", "Fil à souder sans plomb 0,8 mm", "CONS", nil, nil, "SN100C-08-250", "Stannol", 18.0, 1, "BENCH", 3, 1, nil, "roll" ],
    [ :iron, "Soldering station", "Station de soudage", "TOOL", nil, nil, "WE1010", "Weller", 120.0, 0, "TOOLS", 4, 0, nil ]
  ].freeze

  REASONS = {
    en: [ "Workshop: build your first circuit", "Member project", "Repair café", "Prototype", "Arduino introduction" ],
    fr: [ "Atelier : premier circuit", "Projet d’un membre", "Repair café", "Prototype", "Initiation Arduino" ]
  }.freeze

  def self.open_for!(user)
    existing = user.organizations.where(demo: true).find { |organization| user.owner_of?(organization) }
    existing || new(user).create!
  end

  def initialize(user)
    @user = user
    @language = I18n.locale.to_s.start_with?("fr") ? :fr : :en
  end

  def create!
    ActivityEvent.without_recording do
      ActiveRecord::Base.transaction do
        @organization = Organization.create!(name: text("Demo workshop", "Atelier de démo"), demo: true,
                                             onboarding_dismissed_at: Time.current)
        @organization.organization_memberships.create!(user: @user, role: "owner")
        OrganizationTemplate.apply!(@organization, :makerspace, log: false)

        create_parts
        create_orders
        create_projects
        create_loans
        @organization
      end
    end
  end

  private

  def text(en, fr)
    @language == :fr ? fr : en
  end

  def suppliers
    @suppliers ||= @organization.suppliers.where.not(catalog_provider: nil).index_by(&:catalog_provider)
  end

  def zone(code)
    @zones ||= @organization.storage_locations.where.not(code: nil).index_by(&:code)
    @zones.fetch(code)
  end

  def create_parts
    categories = @organization.categories.where.not(code: nil).index_by(&:code)
    footprints = @organization.footprints.index_by(&:name)
    reasons = REASONS.fetch(@language)
    @parts = {}

    PARTS.each_with_index do |(key, en, fr, category, footprint, value, mpn, manufacturer, price, min, zone_code, received, used, supplier, unit), index|
      part = @organization.parts.create!(
        name: text(en, fr), category: categories.fetch(category), footprint: footprints[footprint],
        value: value, mpn: mpn, manufacturer: manufacturer, unit_price: price, unit: unit || "piece",
        min_stock_threshold: min, status: "active", created_at: 45.days.ago
      )
      link_supplier(part, supplier, price) if supplier
      @parts[key] = part

      # Stocked five to six weeks ago, then used a little at a time over the
      # last month so the dashboard chart and the consumption figures have
      # something to show.
      move(part, zone_code, received, text("Initial stock", "Stock initial"), (40 - index % 5).days.ago)
      spread(used, index).each_with_index do |(quantity, days_ago), step|
        move(part, zone_code, -quantity, reasons[(index + step) % reasons.size], days_ago.days.ago - step.hours)
      end
    end
  end

  # Splits +total+ into up to four uses on distinct days within the last month.
  def spread(total, seed)
    return [] unless total.positive?

    random = Random.new(seed)
    count = [ total, 4 ].min
    shares = Array.new(count) { total / count }
    shares[0] += total - shares.sum
    days = (1..28).to_a.sample(count, random: random).sort.reverse
    shares.zip(days)
  end

  def move(part, zone_code, quantity, reason, at)
    @organization.stock_movements.create!(
      part: part, storage_location: zone(zone_code), user: @user,
      movement_type: quantity.positive? ? "in" : "out", quantity_delta: quantity,
      reason: reason, created_at: at, updated_at: at
    )
  end

  def link_supplier(part, provider, price)
    breaks = [ { "quantity" => 1, "unit_price" => price }, { "quantity" => 100, "unit_price" => (price * 0.7).round(4) } ]
    part.part_suppliers.create!(supplier: suppliers.fetch(provider), is_preferred: true, unit_price: price,
                                supplier_sku: part.mpn, lead_time_days: provider == "lcsc" ? 12 : 4,
                                price_breaks: breaks)
  end

  def create_orders
    # Already received (the parts' initial stock), on its way, and late.
    order(suppliers.fetch("digikey"), "received", 38.days.ago, 34.days.ago, atmega: 20)
    order(suppliers.fetch("lcsc"), "shipped", 6.days.ago, 3.days.from_now, r1k: 500, c100n: 500)
    order(suppliers.fetch("mouser"), "pending", 12.days.ago, 3.days.ago, esp32: 10, r220: 200)
  end

  # Created in its final status: no ledger replay (the received order's stock
  # is already in the initial movements).
  def order(supplier, status, ordered_at, expected, lines)
    order = @organization.orders.new(supplier: supplier, status: status, ordered_at: ordered_at.to_date,
                                     expected_delivery: expected.to_date)
    order.save_with_generated_reference! { Order.next_reference(@organization, supplier, date: ordered_at.to_date) }
    lines.each do |key, quantity|
      part = @parts.fetch(key)
      order.order_lines.create!(part: part, quantity: quantity, unit_price: part.unit_price)
    end
    order.recalculate_total!
  end

  def create_projects
    project(text("Weather station", "Station météo"), "confirmed",
            esp32: 1, bme280: 1, r10k: 4, c100n: 6, ams1117: 1, headers: 2, lcd: 1)
    project(text("LED badge", "Badge LED"), "draft", led_red: 8, r220: 8, atmega: 1, headers: 1)
  end

  def project(name, status, lines)
    project = @organization.projects.new(name: name, status: status, reserved_at: (Time.current if status == "confirmed"))
    project.save_with_generated_reference! { Project.next_reference(@organization) }
    lines.each do |key, quantity|
      part = @parts.fetch(key)
      project.project_lines.create!(part: part, designation: part.name, raw_reference: part.mpn, quantity: quantity, match_type: "manual")
    end
  end

  def create_loans
    loan(text("Camille (member)", "Camille (membre)"), 3.days.ago, iron: 1)
    loan(text("Robotics club", "Club robotique"), 10.days.from_now, uno: 2)
  end

  def loan(borrower, due, lines)
    loan = @organization.loans.new(borrower_name: borrower, due_on: due.to_date)
    lines.each do |key, quantity|
      part = @parts.fetch(key)
      loan.loan_lines.build(part: part, quantity: quantity, storage_location: part.part_storages.first.storage_location)
    end
    loan.lend!(user: @user)
  end
end

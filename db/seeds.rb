# frozen_string_literal: true

# This file seeds the database with sample data for development/testing.
# Run with: bin/rails db:seed

puts "Seeding database..."

# =============================================================================
# Users
# =============================================================================
puts "Creating users..."

admin_user = User.find_or_create_by!(email: "admin@example.com") do |user|
  user.firstname = "Admin"
  user.lastname = "User"
  user.password = "password123"
end

test_user = User.find_or_create_by!(email: "test@example.com") do |user|
  user.firstname = "Test"
  user.lastname = "User"
  user.password = "password123"
end

puts "  Created #{User.count} users"

# =============================================================================
# Organizations
# =============================================================================
puts "Creating organizations..."

# Get or create the main organization (created automatically for admin_user)
org = admin_user.organizations.first
if org.nil?
  org = Organization.create!(
    name: "Demo Electronics",
    email: "contact@demo-electronics.com",
    phone: "+1 555-0100",
    address_line1: "123 Tech Street",
    city: "San Francisco",
    postcode: "94102",
    country: "USA"
  )

  OrganizationMembership.create!(
    user: admin_user,
    organization: org,
    role: "owner"
  )
end

# Add test_user as member
OrganizationMembership.find_or_create_by!(user: test_user, organization: org) do |m|
  m.role = "member"
end

puts "  Created #{Organization.count} organizations"

# =============================================================================
# Categories
# =============================================================================
puts "Creating categories..."

categories_data = [
  { name: "Resistors", icon: "resistor", color: "#ef4444", description: "Fixed and variable resistors" },
  { name: "Capacitors", icon: "capacitor", color: "#f97316", description: "Ceramic, electrolytic, film capacitors" },
  { name: "Inductors", icon: "inductor", color: "#eab308", description: "Inductors and coils" },
  { name: "Semiconductors", icon: "chip", color: "#22c55e", description: "Diodes, transistors, ICs" },
  { name: "Connectors", icon: "plug", color: "#3b82f6", description: "Headers, terminals, sockets" },
  { name: "Electromechanical", icon: "switch", color: "#8b5cf6", description: "Switches, relays, buttons" },
  { name: "Optoelectronics", icon: "lightbulb", color: "#ec4899", description: "LEDs, displays, optocouplers" },
  { name: "Passives", icon: "component", color: "#6b7280", description: "Other passive components" }
]

categories = {}
categories_data.each do |data|
  categories[data[:name]] = Category.find_or_create_by!(organization: org, name: data[:name]) do |c|
    c.icon = data[:icon]
    c.color = data[:color]
    c.description = data[:description]
  end
end

# Subcategories
subcategories_data = [
  { name: "SMD Resistors", parent: "Resistors" },
  { name: "Through-Hole Resistors", parent: "Resistors" },
  { name: "Potentiometers", parent: "Resistors" },
  { name: "Ceramic Capacitors", parent: "Capacitors" },
  { name: "Electrolytic Capacitors", parent: "Capacitors" },
  { name: "Film Capacitors", parent: "Capacitors" },
  { name: "Diodes", parent: "Semiconductors" },
  { name: "Transistors", parent: "Semiconductors" },
  { name: "Integrated Circuits", parent: "Semiconductors" },
  { name: "Microcontrollers", parent: "Semiconductors" },
  { name: "LEDs", parent: "Optoelectronics" },
  { name: "Displays", parent: "Optoelectronics" }
]

subcategories_data.each do |data|
  Category.find_or_create_by!(organization: org, name: data[:name]) do |c|
    c.parent = categories[data[:parent]]
  end
end

puts "  Created #{Category.count} categories"

# =============================================================================
# Footprints
# =============================================================================
puts "Creating footprints..."

footprints_data = [
  # SMD Resistors/Capacitors
  { name: "0201", mounting_type: "SMD", description: "0.6mm x 0.3mm" },
  { name: "0402", mounting_type: "SMD", description: "1.0mm x 0.5mm" },
  { name: "0603", mounting_type: "SMD", description: "1.6mm x 0.8mm" },
  { name: "0805", mounting_type: "SMD", description: "2.0mm x 1.25mm" },
  { name: "1206", mounting_type: "SMD", description: "3.2mm x 1.6mm" },
  { name: "1210", mounting_type: "SMD", description: "3.2mm x 2.5mm" },
  { name: "2010", mounting_type: "SMD", description: "5.0mm x 2.5mm" },
  { name: "2512", mounting_type: "SMD", description: "6.3mm x 3.2mm" },
  # Through-hole
  { name: "Axial", mounting_type: "Through-hole", description: "Axial lead component" },
  { name: "Radial", mounting_type: "Through-hole", description: "Radial lead component" },
  { name: "DIP-8", mounting_type: "Through-hole", description: "8-pin DIP package" },
  { name: "DIP-14", mounting_type: "Through-hole", description: "14-pin DIP package" },
  { name: "DIP-16", mounting_type: "Through-hole", description: "16-pin DIP package" },
  { name: "TO-92", mounting_type: "Through-hole", description: "TO-92 transistor package" },
  { name: "TO-220", mounting_type: "Through-hole", description: "TO-220 power package" },
  # SMD ICs
  { name: "SOT-23", mounting_type: "SMD", description: "Small outline transistor" },
  { name: "SOT-223", mounting_type: "SMD", description: "SOT-223 package" },
  { name: "SOIC-8", mounting_type: "SMD", description: "8-pin SOIC" },
  { name: "SOIC-14", mounting_type: "SMD", description: "14-pin SOIC" },
  { name: "SOIC-16", mounting_type: "SMD", description: "16-pin SOIC" },
  { name: "TQFP-32", mounting_type: "SMD", description: "32-pin TQFP" },
  { name: "TQFP-44", mounting_type: "SMD", description: "44-pin TQFP" },
  { name: "QFN-32", mounting_type: "SMD", description: "32-pin QFN" },
  { name: "BGA-256", mounting_type: "SMD", description: "256-ball BGA" }
]

footprints = {}
footprints_data.each do |data|
  footprints[data[:name]] = Footprint.find_or_create_by!(organization: org, name: data[:name]) do |f|
    f.mounting_type = data[:mounting_type]
    f.description = data[:description]
  end
end

puts "  Created #{Footprint.count} footprints"

# =============================================================================
# Tags
# =============================================================================
puts "Creating tags..."

tags_data = [
  { name: "RoHS", color: "#22c55e", description: "RoHS compliant component" },
  { name: "Lead-Free", color: "#10b981", description: "Lead-free component" },
  { name: "Automotive", color: "#f59e0b", description: "Automotive grade" },
  { name: "Military", color: "#6366f1", description: "Military spec" },
  { name: "Low Stock", color: "#ef4444", description: "Running low on stock" },
  { name: "Obsolete", color: "#6b7280", description: "End of life" },
  { name: "New", color: "#3b82f6", description: "Recently added" },
  { name: "Popular", color: "#ec4899", description: "Frequently used" },
  { name: "Critical", color: "#dc2626", description: "Critical component" },
  { name: "Project A", color: "#8b5cf6", description: "Used in Project A" }
]

tags = {}
tags_data.each do |data|
  tags[data[:name]] = Tag.find_or_create_by!(organization: org, name: data[:name]) do |t|
    t.color = data[:color]
    t.description = data[:description]
  end
end

puts "  Created #{Tag.count} tags"

# =============================================================================
# Suppliers
# =============================================================================
puts "Creating suppliers..."

suppliers_data = [
  {
    name: "DigiKey",
    email: "orders@digikey.com",
    website: "https://www.digikey.com",
    phone: "+1 800-344-4539",
    country: "USA"
  },
  {
    name: "Mouser Electronics",
    email: "sales@mouser.com",
    website: "https://www.mouser.com",
    phone: "+1 800-346-6873",
    country: "USA"
  },
  {
    name: "Farnell",
    email: "sales@farnell.com",
    website: "https://www.farnell.com",
    phone: "+44 330 311 1555",
    country: "UK"
  },
  {
    name: "RS Components",
    email: "sales@rs-online.com",
    website: "https://www.rs-online.com",
    phone: "+44 345 850 2222",
    country: "UK"
  },
  {
    name: "LCSC",
    email: "support@lcsc.com",
    website: "https://www.lcsc.com",
    country: "China"
  }
]

suppliers = {}
suppliers_data.each do |data|
  suppliers[data[:name]] = Supplier.find_or_create_by!(organization: org, name: data[:name]) do |s|
    s.email = data[:email]
    s.website = data[:website]
    s.phone = data[:phone]
    s.country = data[:country]
  end
end

puts "  Created #{Supplier.count} suppliers"

# =============================================================================
# Parts
# =============================================================================
puts "Creating parts..."

resistors_cat = Category.find_by(organization: org, name: "SMD Resistors") || categories["Resistors"]
capacitors_cat = Category.find_by(organization: org, name: "Ceramic Capacitors") || categories["Capacitors"]
leds_cat = Category.find_by(organization: org, name: "LEDs") || categories["Optoelectronics"]
mcu_cat = Category.find_by(organization: org, name: "Microcontrollers") || categories["Semiconductors"]
diodes_cat = Category.find_by(organization: org, name: "Diodes") || categories["Semiconductors"]

parts_data = [
  # Resistors
  {
    name: "10K Resistor",
    mpn: "RC0805FR-0710KL",
    sku: "RES-10K-0805",
    manufacturer: "Yageo",
    value: "10K",
    tolerance: "1%",
    category: resistors_cat,
    footprint: footprints["0805"],
    unit_price: 0.01,
    min_stock_threshold: 100,
    target_stock: 500,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["DigiKey"],
    tag_list: %w[RoHS Popular]
  },
  {
    name: "1K Resistor",
    mpn: "RC0805FR-071KL",
    sku: "RES-1K-0805",
    manufacturer: "Yageo",
    value: "1K",
    tolerance: "1%",
    category: resistors_cat,
    footprint: footprints["0805"],
    unit_price: 0.01,
    min_stock_threshold: 100,
    target_stock: 500,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["DigiKey"],
    tag_list: %w[RoHS Popular]
  },
  {
    name: "100R Resistor",
    mpn: "RC0805FR-07100RL",
    sku: "RES-100R-0805",
    manufacturer: "Yageo",
    value: "100R",
    tolerance: "1%",
    category: resistors_cat,
    footprint: footprints["0805"],
    unit_price: 0.01,
    min_stock_threshold: 100,
    target_stock: 500,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  {
    name: "4.7K Resistor",
    mpn: "RC0603FR-074K7L",
    sku: "RES-4K7-0603",
    manufacturer: "Yageo",
    value: "4.7K",
    tolerance: "1%",
    category: resistors_cat,
    footprint: footprints["0603"],
    unit_price: 0.008,
    min_stock_threshold: 100,
    target_stock: 500,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  # Capacitors
  {
    name: "100nF Ceramic Capacitor",
    mpn: "CL21B104KBCNNNC",
    sku: "CAP-100N-0805",
    manufacturer: "Samsung",
    value: "100nF",
    voltage_rating: "50V",
    category: capacitors_cat,
    footprint: footprints["0805"],
    unit_price: 0.02,
    min_stock_threshold: 100,
    target_stock: 500,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["LCSC"],
    tag_list: %w[RoHS Popular]
  },
  {
    name: "10uF Ceramic Capacitor",
    mpn: "CL21A106KAYNNNE",
    sku: "CAP-10U-0805",
    manufacturer: "Samsung",
    value: "10uF",
    voltage_rating: "25V",
    category: capacitors_cat,
    footprint: footprints["0805"],
    unit_price: 0.05,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  {
    name: "1uF Ceramic Capacitor",
    mpn: "CL21B105KAFNNNE",
    sku: "CAP-1U-0805",
    manufacturer: "Samsung",
    value: "1uF",
    voltage_rating: "50V",
    category: capacitors_cat,
    footprint: footprints["0805"],
    unit_price: 0.03,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  # LEDs
  {
    name: "Red LED 0805",
    mpn: "19-217/R6C-AL1M2VY/3T",
    sku: "LED-RED-0805",
    manufacturer: "Everlight",
    value: "Red",
    category: leds_cat,
    footprint: footprints["0805"],
    unit_price: 0.05,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  {
    name: "Green LED 0805",
    mpn: "19-217/GHC-YR1S2/3T",
    sku: "LED-GRN-0805",
    manufacturer: "Everlight",
    value: "Green",
    category: leds_cat,
    footprint: footprints["0805"],
    unit_price: 0.05,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  {
    name: "Blue LED 0805",
    mpn: "19-217/BHC-ZL1M2RY/3T",
    sku: "LED-BLU-0805",
    manufacturer: "Everlight",
    value: "Blue",
    category: leds_cat,
    footprint: footprints["0805"],
    unit_price: 0.06,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  # MCUs
  {
    name: "ATmega328P",
    mpn: "ATMEGA328P-AU",
    sku: "MCU-328P",
    manufacturer: "Microchip",
    description: "8-bit AVR Microcontroller with 32KB Flash",
    category: mcu_cat,
    footprint: footprints["TQFP-32"],
    unit_price: 2.50,
    min_stock_threshold: 10,
    target_stock: 50,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["DigiKey"],
    tag_list: %w[RoHS Popular]
  },
  {
    name: "STM32F103C8T6",
    mpn: "STM32F103C8T6",
    sku: "MCU-STM32F103",
    manufacturer: "STMicroelectronics",
    description: "ARM Cortex-M3 32-bit MCU with 64KB Flash",
    category: mcu_cat,
    footprint: footprints["TQFP-44"],
    unit_price: 3.50,
    min_stock_threshold: 10,
    target_stock: 50,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["LCSC"],
    tag_list: [ "RoHS", "Popular", "Project A" ]
  },
  {
    name: "ESP32-WROOM-32",
    mpn: "ESP32-WROOM-32E",
    sku: "MCU-ESP32",
    manufacturer: "Espressif",
    description: "WiFi + Bluetooth MCU Module",
    category: mcu_cat,
    unit_price: 4.00,
    min_stock_threshold: 5,
    target_stock: 20,
    status: "active",
    rohs_compliant: true,
    preferred_supplier: suppliers["LCSC"],
    tag_list: %w[RoHS New]
  },
  # Diodes
  {
    name: "1N4148 Signal Diode",
    mpn: "1N4148W-7-F",
    sku: "DIO-1N4148",
    manufacturer: "Diodes Inc.",
    description: "Fast switching diode",
    category: diodes_cat,
    footprint: footprints["SOT-23"],
    unit_price: 0.02,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  {
    name: "1N5819 Schottky Diode",
    mpn: "SS14",
    sku: "DIO-SS14",
    manufacturer: "Diodes Inc.",
    description: "1A 40V Schottky diode",
    category: diodes_cat,
    footprint: footprints["SOT-23"],
    unit_price: 0.05,
    min_stock_threshold: 50,
    target_stock: 200,
    status: "active",
    rohs_compliant: true,
    tag_list: %w[RoHS]
  },
  # Discontinued part example
  {
    name: "LM7805 Voltage Regulator (Obsolete)",
    mpn: "LM7805CT",
    sku: "REG-7805-OLD",
    manufacturer: "Texas Instruments",
    description: "5V 1A Linear Regulator - DISCONTINUED",
    category: categories["Semiconductors"],
    footprint: footprints["TO-220"],
    unit_price: 0.50,
    min_stock_threshold: 5,
    target_stock: 10,
    status: "discontinued",
    rohs_compliant: false,
    tag_list: %w[Obsolete]
  }
]

parts_data.each do |data|
  tag_names = data.delete(:tag_list) || []

  part = Part.find_or_create_by!(organization: org, mpn: data[:mpn]) do |p|
    p.name = data[:name]
    p.sku = data[:sku]
    p.manufacturer = data[:manufacturer]
    p.description = data[:description]
    p.value = data[:value]
    p.tolerance = data[:tolerance]
    p.voltage_rating = data[:voltage_rating]
    p.category = data[:category]
    p.footprint = data[:footprint]
    p.unit_price = data[:unit_price]
    p.min_stock_threshold = data[:min_stock_threshold]
    p.target_stock = data[:target_stock]
    p.status = data[:status]
    p.rohs_compliant = data[:rohs_compliant]
    p.preferred_supplier = data[:preferred_supplier]
  end

  # Add tags
  tag_names.each do |tag_name|
    tag = tags[tag_name]
    PartTag.find_or_create_by!(part: part, tag: tag) if tag
  end
end

puts "  Created #{Part.count} parts"

# =============================================================================
# Summary
# =============================================================================
puts ""
puts "=" * 60
puts "Seed completed successfully!"
puts "=" * 60
puts ""
puts "Created:"
puts "  - #{User.count} users"
puts "  - #{Organization.count} organizations"
puts "  - #{Category.count} categories"
puts "  - #{Footprint.count} footprints"
puts "  - #{Tag.count} tags"
puts "  - #{Supplier.count} suppliers"
puts "  - #{Part.count} parts"
puts ""
puts "Login credentials:"
puts "  - admin@example.com / password123 (Owner)"
puts "  - test@example.com / password123 (Member)"
puts ""

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_27_120000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "code"
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_categories_on_organization_id_and_code"
    t.index ["organization_id", "name"], name: "index_categories_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_categories_on_organization_id"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "footprints", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "mounting_type"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mounting_type"], name: "index_footprints_on_mounting_type"
    t.index ["organization_id", "name"], name: "index_footprints_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_footprints_on_organization_id"
  end

  create_table "order_line_allocations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "order_line_id", null: false
    t.integer "quantity", null: false
    t.integer "storage_location_id", null: false
    t.datetime "updated_at", null: false
    t.index ["order_line_id"], name: "index_order_line_allocations_on_order_line_id"
    t.index ["storage_location_id"], name: "index_order_line_allocations_on_storage_location_id"
  end

  create_table "order_lines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "order_id", null: false
    t.integer "part_id", null: false
    t.integer "quantity", null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_lines_on_order_id"
    t.index ["part_id"], name: "index_order_lines_on_part_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "expected_delivery"
    t.text "notes"
    t.date "ordered_at"
    t.integer "organization_id", null: false
    t.string "reference"
    t.string "status", default: "pending", null: false
    t.integer "supplier_id", null: false
    t.decimal "total_amount", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["organization_id", "reference"], name: "index_orders_on_organization_id_and_reference", unique: true, where: "reference IS NOT NULL AND reference != ''"
    t.index ["organization_id"], name: "index_orders_on_organization_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["supplier_id"], name: "index_orders_on_supplier_id"
  end

  create_table "organization_memberships", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.integer "invited_by_id"
    t.integer "organization_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["active"], name: "index_organization_memberships_on_active"
    t.index ["invitation_token"], name: "index_organization_memberships_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_organization_memberships_on_invited_by_id"
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_org_memberships_on_user_and_org", unique: true
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.boolean "allow_negative_stock", default: false, null: false
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.integer "default_low_stock_threshold", default: 50, null: false
    t.text "digikey_access_token"
    t.text "digikey_client_id"
    t.text "digikey_client_secret"
    t.text "digikey_refresh_token"
    t.datetime "digikey_token_expires_at"
    t.string "email"
    t.string "ipn_charset", default: "numeric", null: false
    t.integer "ipn_digits", default: 5, null: false
    t.string "ipn_generation_mode", default: "incremental", null: false
    t.integer "ipn_next_sequence", default: 1, null: false
    t.string "ipn_prefix", default: "MS", null: false
    t.string "ipn_separator", default: "-", null: false
    t.boolean "ipn_use_category_code", default: true, null: false
    t.text "mouser_api_key"
    t.text "mouser_order_api_key"
    t.string "name", null: false
    t.boolean "personal", default: false, null: false
    t.string "phone"
    t.string "postcode"
    t.string "timezone", default: "Europe/Paris", null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["email"], name: "index_organizations_on_email"
    t.index ["name"], name: "index_organizations_on_name"
  end

  create_table "part_storages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "part_id", null: false
    t.integer "quantity", default: 0, null: false
    t.integer "storage_location_id", null: false
    t.datetime "updated_at", null: false
    t.index ["part_id", "storage_location_id"], name: "index_part_storages_on_part_and_location", unique: true
    t.index ["part_id"], name: "index_part_storages_on_part_id"
    t.index ["storage_location_id"], name: "index_part_storages_on_storage_location_id"
  end

  create_table "part_suppliers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_preferred", default: false, null: false
    t.integer "lead_time_days"
    t.text "notes"
    t.integer "part_id", null: false
    t.integer "supplier_id", null: false
    t.string "supplier_sku"
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["part_id", "supplier_id"], name: "index_part_suppliers_on_part_id_and_supplier_id", unique: true
    t.index ["part_id"], name: "index_part_suppliers_on_part_id"
    t.index ["supplier_id"], name: "index_part_suppliers_on_supplier_id"
    t.index ["supplier_sku"], name: "index_part_suppliers_on_supplier_sku"
  end

  create_table "part_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "part_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["part_id", "tag_id"], name: "index_part_tags_on_part_id_and_tag_id", unique: true
    t.index ["part_id"], name: "index_part_tags_on_part_id"
    t.index ["tag_id"], name: "index_part_tags_on_tag_id"
  end

  create_table "parts", force: :cascade do |t|
    t.string "barcode"
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "footprint_id"
    t.string "image_source_url"
    t.string "ipn"
    t.integer "lead_time_days"
    t.string "manufacturer"
    t.integer "min_stock_threshold", default: 0, null: false
    t.string "mpn"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "package_type"
    t.string "power_rating"
    t.boolean "rohs_compliant", default: false
    t.string "sku"
    t.string "status", default: "active", null: false
    t.text "storage_notes"
    t.integer "target_stock"
    t.string "tolerance"
    t.string "unit", default: "piece", null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.string "value"
    t.string "voltage_rating"
    t.index ["category_id"], name: "index_parts_on_category_id"
    t.index ["footprint_id"], name: "index_parts_on_footprint_id"
    t.index ["manufacturer"], name: "index_parts_on_manufacturer"
    t.index ["name"], name: "index_parts_on_name"
    t.index ["organization_id", "barcode"], name: "index_parts_on_organization_id_and_barcode", unique: true, where: "barcode IS NOT NULL"
    t.index ["organization_id", "ipn"], name: "index_parts_on_organization_id_and_ipn", unique: true, where: "ipn IS NOT NULL"
    t.index ["organization_id", "mpn"], name: "index_parts_on_organization_id_and_mpn", unique: true, where: "mpn IS NOT NULL"
    t.index ["organization_id", "sku"], name: "index_parts_on_organization_id_and_sku", unique: true, where: "sku IS NOT NULL"
    t.index ["organization_id"], name: "index_parts_on_organization_id"
    t.index ["status"], name: "index_parts_on_status"
    t.index ["value"], name: "index_parts_on_value"
  end

  create_table "project_lines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "designation"
    t.string "match_type", default: "none", null: false
    t.integer "part_id"
    t.integer "project_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "raw_reference"
    t.datetime "updated_at", null: false
    t.index ["part_id"], name: "index_project_lines_on_part_id"
    t.index ["project_id"], name: "index_project_lines_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "reference"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "reference"], name: "index_projects_on_organization_id_and_reference", unique: true, where: "reference IS NOT NULL AND reference != ''"
    t.index ["organization_id"], name: "index_projects_on_organization_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "movement_type", null: false
    t.integer "organization_id", null: false
    t.integer "part_id", null: false
    t.integer "quantity_delta", null: false
    t.text "reason"
    t.string "reference"
    t.integer "storage_location_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["created_at"], name: "index_stock_movements_on_created_at"
    t.index ["movement_type"], name: "index_stock_movements_on_movement_type"
    t.index ["organization_id"], name: "index_stock_movements_on_organization_id"
    t.index ["part_id"], name: "index_stock_movements_on_part_id"
    t.index ["storage_location_id"], name: "index_stock_movements_on_storage_location_id"
    t.index ["user_id"], name: "index_stock_movements_on_user_id"
  end

  create_table "storage_locations", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "location_type", null: false
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_storage_locations_on_code"
    t.index ["location_type"], name: "index_storage_locations_on_location_type"
    t.index ["organization_id", "name"], name: "index_storage_locations_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_storage_locations_on_organization_id"
    t.index ["parent_id"], name: "index_storage_locations_on_parent_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "catalog_provider"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.integer "organization_id", null: false
    t.string "phone"
    t.string "postcode"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["organization_id", "catalog_provider"], name: "index_suppliers_on_organization_id_and_catalog_provider", unique: true, where: "catalog_provider IS NOT NULL"
    t.index ["organization_id", "name"], name: "index_suppliers_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_suppliers_on_organization_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_tags_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_tags_on_organization_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "firstname", default: "", null: false
    t.string "lastname", default: "", null: false
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "categories", "organizations"
  add_foreign_key "footprints", "organizations"
  add_foreign_key "order_line_allocations", "order_lines"
  add_foreign_key "order_line_allocations", "storage_locations"
  add_foreign_key "order_lines", "orders"
  add_foreign_key "order_lines", "parts"
  add_foreign_key "orders", "organizations"
  add_foreign_key "orders", "suppliers"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "organization_memberships", "users", column: "invited_by_id"
  add_foreign_key "part_storages", "parts"
  add_foreign_key "part_storages", "storage_locations"
  add_foreign_key "part_suppliers", "parts"
  add_foreign_key "part_suppliers", "suppliers"
  add_foreign_key "part_tags", "parts"
  add_foreign_key "part_tags", "tags"
  add_foreign_key "parts", "categories"
  add_foreign_key "parts", "footprints"
  add_foreign_key "parts", "organizations"
  add_foreign_key "project_lines", "parts"
  add_foreign_key "project_lines", "projects"
  add_foreign_key "projects", "organizations"
  add_foreign_key "stock_movements", "organizations"
  add_foreign_key "stock_movements", "parts"
  add_foreign_key "stock_movements", "storage_locations"
  add_foreign_key "stock_movements", "users"
  add_foreign_key "storage_locations", "organizations"
  add_foreign_key "storage_locations", "storage_locations", column: "parent_id"
  add_foreign_key "suppliers", "organizations"
  add_foreign_key "tags", "organizations"
end

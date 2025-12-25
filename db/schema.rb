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

ActiveRecord::Schema[8.1].define(version: 2025_12_25_215111) do
  create_table "categories", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
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
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.string "phone"
    t.string "postcode"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["email"], name: "index_organizations_on_email"
    t.index ["name"], name: "index_organizations_on_name"
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
    t.integer "lead_time_days"
    t.string "manufacturer"
    t.integer "min_stock_threshold", default: 0, null: false
    t.string "mpn"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "package_type"
    t.string "power_rating"
    t.integer "preferred_supplier_id"
    t.boolean "rohs_compliant", default: false
    t.string "sku"
    t.string "status", default: "active", null: false
    t.text "storage_notes"
    t.string "supplier_sku"
    t.integer "target_stock"
    t.string "tolerance"
    t.decimal "unit_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.string "value"
    t.string "voltage_rating"
    t.index ["barcode"], name: "index_parts_on_barcode", unique: true, where: "barcode IS NOT NULL"
    t.index ["category_id"], name: "index_parts_on_category_id"
    t.index ["footprint_id"], name: "index_parts_on_footprint_id"
    t.index ["manufacturer"], name: "index_parts_on_manufacturer"
    t.index ["name"], name: "index_parts_on_name"
    t.index ["organization_id", "mpn"], name: "index_parts_on_organization_id_and_mpn", unique: true, where: "mpn IS NOT NULL"
    t.index ["organization_id", "sku"], name: "index_parts_on_organization_id_and_sku", unique: true, where: "sku IS NOT NULL"
    t.index ["organization_id"], name: "index_parts_on_organization_id"
    t.index ["preferred_supplier_id"], name: "index_parts_on_preferred_supplier_id"
    t.index ["status"], name: "index_parts_on_status"
    t.index ["value"], name: "index_parts_on_value"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
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

  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "categories", "organizations"
  add_foreign_key "footprints", "organizations"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "organization_memberships", "users", column: "invited_by_id"
  add_foreign_key "part_tags", "parts"
  add_foreign_key "part_tags", "tags"
  add_foreign_key "parts", "categories"
  add_foreign_key "parts", "footprints"
  add_foreign_key "parts", "organizations"
  add_foreign_key "parts", "suppliers", column: "preferred_supplier_id"
  add_foreign_key "suppliers", "organizations"
  add_foreign_key "tags", "organizations"
end

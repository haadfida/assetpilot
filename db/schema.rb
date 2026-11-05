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

ActiveRecord::Schema[8.1].define(version: 2026_11_05_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "agent_runs", force: :cascade do |t|
    t.text "prompt", null: false
    t.string "model", null: false
    t.string "mode", null: false
    t.string "status", default: "queued", null: false
    t.string "replay_slug"
    t.string "recorded"
    t.integer "iterations", default: 0, null: false
    t.string "stop_reason"
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cache_read_input_tokens", default: 0, null: false
    t.integer "cache_creation_input_tokens", default: 0, null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_agent_runs_on_created_at"
    t.index ["status"], name: "index_agent_runs_on_status"
    t.check_constraint "mode::text = ANY (ARRAY['live'::character varying, 'replay'::character varying]::text[])", name: "agent_runs_mode_check"
  end

  create_table "agent_steps", force: :cascade do |t|
    t.bigint "agent_run_id", null: false
    t.integer "position", null: false
    t.string "kind", null: false
    t.integer "iteration", default: 0, null: false
    t.text "content"
    t.string "tool_use_id"
    t.string "tool_name"
    t.jsonb "input"
    t.jsonb "output"
    t.boolean "is_error", default: false, null: false
    t.integer "elapsed_ms"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id", "position"], name: "index_agent_steps_on_agent_run_id_and_position", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['text'::character varying, 'progress'::character varying, 'tool_use'::character varying, 'tool_result'::character varying, 'error'::character varying]::text[])", name: "agent_steps_kind_check"
  end

  create_table "assets", force: :cascade do |t|
    t.string "tag", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.string "status", default: "available", null: false
    t.string "serial"
    t.date "purchased_on"
    t.date "warranty_until"
    t.bigint "location_id"
    t.bigint "custodian_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "((((((COALESCE(name, ''::character varying))::text || ' '::text) || (COALESCE(tag, ''::character varying))::text) || ' '::text) || (COALESCE(serial, ''::character varying))::text)) gin_trgm_ops", name: "index_assets_on_search_text", using: :gin
    t.index ["category"], name: "index_assets_on_category"
    t.index ["custodian_id"], name: "index_assets_on_custodian_id"
    t.index ["location_id"], name: "index_assets_on_location_id"
    t.index ["serial"], name: "index_assets_on_serial"
    t.index ["status"], name: "index_assets_on_status"
    t.index ["tag"], name: "index_assets_on_tag", unique: true
    t.index ["warranty_until"], name: "index_assets_on_warranty_until"
  end

  create_table "checkouts", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.bigint "person_id", null: false
    t.datetime "out_at", null: false
    t.datetime "due_at", null: false
    t.datetime "in_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_checkouts_on_asset_id"
    t.index ["asset_id"], name: "index_checkouts_one_open_per_asset", unique: true, where: "(in_at IS NULL)"
    t.index ["due_at"], name: "index_checkouts_open_due", where: "(in_at IS NULL)"
    t.index ["person_id"], name: "index_checkouts_on_person_id"
  end

  create_table "dependencies", force: :cascade do |t|
    t.string "source_type", null: false
    t.bigint "source_id", null: false
    t.string "target_type", null: false
    t.bigint "target_id", null: false
    t.string "kind", default: "depends_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_id", "target_type", "target_id", "kind"], name: "index_dependencies_uniqueness", unique: true
    t.index ["target_type", "target_id"], name: "index_dependencies_on_target"
    t.check_constraint "(source_type::text = ANY (ARRAY['Asset'::character varying, 'Service'::character varying]::text[])) AND (target_type::text = ANY (ARRAY['Asset'::character varying, 'Service'::character varying]::text[]))", name: "dependencies_types_check"
  end

  create_table "locations", force: :cascade do |t|
    t.string "name", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_locations_on_name", unique: true
  end

  create_table "maintenance_tasks", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.date "due_on", null: false
    t.string "kind", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_maintenance_tasks_on_asset_id"
    t.index ["status", "due_on"], name: "index_maintenance_tasks_on_status_and_due_on"
  end

  create_table "people", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "department"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_people_on_lower_email", unique: true
    t.index ["department"], name: "index_people_on_department"
  end

  create_table "services", force: :cascade do |t|
    t.string "name", null: false
    t.string "criticality", default: "medium", null: false
    t.bigint "owner_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["criticality"], name: "index_services_on_criticality"
    t.index ["name"], name: "index_services_on_name", unique: true
    t.index ["owner_id"], name: "index_services_on_owner_id"
  end

  add_foreign_key "agent_steps", "agent_runs", on_delete: :cascade
  add_foreign_key "assets", "locations"
  add_foreign_key "assets", "people", column: "custodian_id"
  add_foreign_key "checkouts", "assets"
  add_foreign_key "checkouts", "people"
  add_foreign_key "maintenance_tasks", "assets"
  add_foreign_key "services", "people", column: "owner_id"
end

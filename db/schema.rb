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

ActiveRecord::Schema[7.0].define(version: 2022_07_08_145818) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "document_approval_status_enum", ["awaiting", "approved", "rejected"]
  create_enum "document_status_enum", ["pending", "uploaded", "confirmed"]

  create_table "alembic_version", primary_key: "version_num", id: { type: :string, limit: 32 }, force: :cascade do |t|
  end

  create_table "document_folder", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "document_id", null: false
    t.uuid "folder_id", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["document_id"], name: "ix_document_folder_document_id"
    t.index ["folder_id"], name: "ix_document_folder_folder_id"
    t.index ["id"], name: "ix_document_folder_id", unique: true
  end

  create_table "documents", id: :uuid, default: nil, force: :cascade do |t|
    t.text "name", null: false
    t.integer "label_id"
    t.text "storage_url", null: false
    t.text "content"
    t.enum "status", null: false, enum_type: "document_status_enum"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "ix_documents_id", unique: true
    t.index ["label_id"], name: "ix_documents_label_id"
  end

  create_table "documents_approval", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "document_id", null: false
    t.uuid "approved_by", null: false
    t.enum "status", null: false, enum_type: "document_approval_status_enum"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.text "remark"
    t.index ["approved_by"], name: "ix_documents_approval_approved_by"
    t.index ["document_id"], name: "ix_documents_approval_document_id"
    t.index ["id"], name: "ix_documents_approval_id", unique: true
  end

  create_table "folders", id: :uuid, default: nil, force: :cascade do |t|
    t.text "name", null: false
    t.text "description"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "folders_id_key", unique: true
    t.index ["id"], name: "folders_id_key1", unique: true
  end

  create_table "forms_data", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "document_id", null: false
    t.uuid "schema_id", null: false
    t.jsonb "data", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["document_id"], name: "ix_forms_data_document_id"
    t.index ["id"], name: "ix_forms_data_id", unique: true
    t.index ["schema_id"], name: "ix_forms_data_schema_id"
  end

  create_table "forms_schema", id: :uuid, default: nil, force: :cascade do |t|
    t.text "name", null: false
    t.json "form_schema", null: false
    t.json "ui_schema", null: false
    t.jsonb "data_schema", null: false
    t.text "description"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "ix_forms_schema_id", unique: true
  end

  create_table "jwt_denylist", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["jti"], name: "index_jwt_denylist_on_jti"
  end

  create_table "labels", id: :serial, force: :cascade do |t|
    t.text "name", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "labels_id_key", unique: true
    t.index ["id"], name: "labels_id_key1", unique: true
  end

  create_table "roles", id: :uuid, default: nil, force: :cascade do |t|
    t.text "role", null: false
    t.text "description"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "roles_id_key", unique: true
    t.index ["id"], name: "roles_id_key1", unique: true
  end

  create_table "user", id: :uuid, default: nil, force: :cascade do |t|
    t.text "username", null: false
    t.text "password", null: false
    t.uuid "role_id", null: false
    t.text "description"
    t.datetime "last_active_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["id"], name: "ix_users_id", unique: true
    t.index ["role_id"], name: "ix_users_role_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "document_folder", "documents", name: "document_folder_document_id_fkey"
  add_foreign_key "document_folder", "folders", name: "document_folder_folder_id_fkey"
  add_foreign_key "documents", "labels", name: "documents_label_id_fkey"
  add_foreign_key "documents_approval", "\"user\"", column: "approved_by", name: "documents_approval_approved_by_fkey"
  add_foreign_key "documents_approval", "documents", name: "documents_approval_document_id_fkey"
  add_foreign_key "forms_data", "documents", name: "forms_data_document_id_fkey"
  add_foreign_key "forms_data", "forms_schema", column: "schema_id", name: "forms_data_schema_id_fkey"
  add_foreign_key "user", "roles", name: "users_role_id_fkey"
end

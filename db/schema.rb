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

ActiveRecord::Schema[7.0].define(version: 2024_08_17_161432) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.uuid "record_id", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.uuid "record_id", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_tools", force: :cascade do |t|
    t.string "name"
    t.string "invoke_name"
    t.string "description"
    t.string "invoke_description"
    t.string "category"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_agent_tools_on_category"
    t.index ["category"], name: "index_agent_tools_on_category"
  end

  create_table "agent_tools", force: :cascade do |t|
    t.string "name"
    t.string "invoke_name"
    t.string "description"
    t.string "invoke_description"
    t.string "category"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_agent_tools_on_category"
    t.index ["category"], name: "index_agent_tools_on_category"
  end

  create_table "agent_use_tools", force: :cascade do |t|
    t.bigint "assistant_agent_id", null: false
    t.bigint "agent_tool_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_tool_id"], name: "index_agent_use_tools_on_agent_tool_id"
    t.index ["agent_tool_id"], name: "index_agent_use_tools_on_agent_tool_id"
    t.index ["assistant_agent_id"], name: "index_agent_use_tools_on_assistant_agent_id"
    t.index ["assistant_agent_id"], name: "index_agent_use_tools_on_assistant_agent_id"
  end

  create_table "agent_use_tools", force: :cascade do |t|
    t.bigint "assistant_agent_id", null: false
    t.bigint "agent_tool_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_tool_id"], name: "index_agent_use_tools_on_agent_tool_id"
    t.index ["agent_tool_id"], name: "index_agent_use_tools_on_agent_tool_id"
    t.index ["assistant_agent_id"], name: "index_agent_use_tools_on_assistant_agent_id"
    t.index ["assistant_agent_id"], name: "index_agent_use_tools_on_assistant_agent_id"
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "key", null: false
    t.datetime "expires_at"
    t.boolean "active", default: true
    t.string "tenant", null: false
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_api_keys_on_key", unique: true
    t.index ["key"], name: "index_api_keys_on_key", unique: true
    t.index ["tenant"], name: "index_api_keys_on_tenant"
    t.index ["tenant"], name: "index_api_keys_on_tenant"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "key", null: false
    t.datetime "expires_at"
    t.boolean "active", default: true
    t.string "tenant", null: false
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_api_keys_on_key", unique: true
    t.index ["key"], name: "index_api_keys_on_key", unique: true
    t.index ["tenant"], name: "index_api_keys_on_tenant"
    t.index ["tenant"], name: "index_api_keys_on_tenant"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "assessment_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.jsonb "record"
    t.jsonb "meta"
    t.string "recordable_type"
    t.uuid "recordable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "score", default: "0.0", null: false
    t.integer "questions_count", default: 0, null: false
    t.decimal "full_score", default: "0.0", null: false
    t.index ["recordable_type", "recordable_id"], name: "index_assessment_records_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_assessment_records_on_recordable"
  end

  create_table "assessment_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.jsonb "record"
    t.jsonb "meta"
    t.string "recordable_type"
    t.uuid "recordable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "score", default: "0.0", null: false
    t.integer "questions_count", default: 0, null: false
    t.decimal "full_score", default: "0.0", null: false
    t.index ["recordable_type", "recordable_id"], name: "index_assessment_records_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_assessment_records_on_recordable"
  end

  create_table "assistant_agents", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "system_message"
    t.string "subdomain"
    t.jsonb "llm_config"
    t.jsonb "meta"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "remark"
    t.string "version"
    t.string "name_en"
    t.string "prompt_header"
    t.string "category"
    t.string "helper_agent_system_message"
    t.string "conclude_conversation_message"
    t.index ["category"], name: "index_assistant_agents_on_category"
    t.index ["category"], name: "index_assistant_agents_on_category"
    t.index ["name"], name: "index_assistant_agents_on_name"
    t.index ["name"], name: "index_assistant_agents_on_name"
    t.index ["name_en"], name: "index_assistant_agents_on_name_en"
    t.index ["name_en"], name: "index_assistant_agents_on_name_en"
    t.index ["version"], name: "index_assistant_agents_on_version"
    t.index ["version"], name: "index_assistant_agents_on_version"
  end

  create_table "assistant_agents", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "system_message"
    t.string "subdomain"
    t.jsonb "llm_config"
    t.jsonb "meta"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "remark"
    t.string "version"
    t.string "name_en"
    t.string "prompt_header"
    t.string "category"
    t.string "helper_agent_system_message"
    t.string "conclude_conversation_message"
    t.index ["category"], name: "index_assistant_agents_on_category"
    t.index ["category"], name: "index_assistant_agents_on_category"
    t.index ["name"], name: "index_assistant_agents_on_name"
    t.index ["name"], name: "index_assistant_agents_on_name"
    t.index ["name_en"], name: "index_assistant_agents_on_name_en"
    t.index ["name_en"], name: "index_assistant_agents_on_name_en"
    t.index ["version"], name: "index_assistant_agents_on_version"
    t.index ["version"], name: "index_assistant_agents_on_version"
  end

  create_table "chatbots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.uuid "user_id", null: false
    t.integer "category", default: 0, null: false
    t.jsonb "meta", default: {}
    t.jsonb "source", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_public", default: false, null: false
    t.datetime "expired_at"
    t.integer "access_count", default: 0
    t.string "object_type"
    t.uuid "object_id"
    t.jsonb "assistive_questions", default: [], null: false
    t.boolean "has_chatbot_updated", default: false, null: false
    t.integer "energy_cost", default: 0
    t.string "dify_token"
    t.index ["category"], name: "index_chatbots_on_category"
    t.index ["category"], name: "index_chatbots_on_category"
    t.index ["dify_token"], name: "index_chatbots_on_dify_token"
    t.index ["dify_token"], name: "index_chatbots_on_dify_token"
    t.index ["user_id"], name: "index_chatbots_on_user_id"
    t.index ["user_id"], name: "index_chatbots_on_user_id"
  end

  create_table "chatbots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.uuid "user_id", null: false
    t.integer "category", default: 0, null: false
    t.jsonb "meta", default: {}
    t.jsonb "source", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_public", default: false, null: false
    t.datetime "expired_at"
    t.integer "access_count", default: 0
    t.string "object_type"
    t.uuid "object_id"
    t.jsonb "assistive_questions", default: [], null: false
    t.boolean "has_chatbot_updated", default: false, null: false
    t.integer "energy_cost", default: 0
    t.string "dify_token"
    t.index ["category"], name: "index_chatbots_on_category"
    t.index ["category"], name: "index_chatbots_on_category"
    t.index ["dify_token"], name: "index_chatbots_on_dify_token"
    t.index ["dify_token"], name: "index_chatbots_on_dify_token"
    t.index ["user_id"], name: "index_chatbots_on_user_id"
    t.index ["user_id"], name: "index_chatbots_on_user_id"
  end

  create_table "classification_model_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "classification_model_name", null: false
    t.string "entity_name", null: false
    t.string "description", default: ""
    t.uuid "pervious_version_id"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_name"], name: "index_classification_model_versions_on_entity_name"
    t.index ["entity_name"], name: "index_classification_model_versions_on_entity_name"
    t.index ["pervious_version_id"], name: "index_classification_model_versions_on_pervious_version_id"
    t.index ["pervious_version_id"], name: "index_classification_model_versions_on_pervious_version_id"
  end

  create_table "classification_model_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "classification_model_name", null: false
    t.string "entity_name", null: false
    t.string "description", default: ""
    t.uuid "pervious_version_id"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_name"], name: "index_classification_model_versions_on_entity_name"
    t.index ["entity_name"], name: "index_classification_model_versions_on_entity_name"
    t.index ["pervious_version_id"], name: "index_classification_model_versions_on_pervious_version_id"
    t.index ["pervious_version_id"], name: "index_classification_model_versions_on_pervious_version_id"
  end

  create_table "conceptmaps", force: :cascade do |t|
    t.string "name"
    t.uuid "root_node"
    t.integer "status"
    t.string "introduction"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_node"], name: "index_conceptmaps_on_root_node"
    t.index ["root_node"], name: "index_conceptmaps_on_root_node"
  end

  create_table "conceptmaps", force: :cascade do |t|
    t.string "name"
    t.uuid "root_node"
    t.integer "status"
    t.string "introduction"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_node"], name: "index_conceptmaps_on_root_node"
    t.index ["root_node"], name: "index_conceptmaps_on_root_node"
  end

  create_table "concepts", force: :cascade do |t|
    t.string "source"
    t.string "name"
    t.uuid "root_node"
    t.jsonb "meta", default: {}, null: false
    t.integer "sort"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_node"], name: "index_concepts_on_root_node"
    t.index ["root_node"], name: "index_concepts_on_root_node"
  end

  create_table "concepts", force: :cascade do |t|
    t.string "source"
    t.string "name"
    t.uuid "root_node"
    t.jsonb "meta", default: {}, null: false
    t.integer "sort"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_node"], name: "index_concepts_on_root_node"
    t.index ["root_node"], name: "index_concepts_on_root_node"
  end

  create_table "cors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "description", default: ""
    t.string "url", null: false
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "description", default: ""
    t.string "url", null: false
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dag_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "dag_name"
    t.integer "dag_status", default: 0, null: false
    t.jsonb "meta", default: {}
    t.jsonb "statistic", default: {}
    t.jsonb "dag_meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "airflow_accepted", default: false, null: false
    t.string "tanent"
    t.string "user_type", default: "User", null: false
    t.index ["airflow_accepted"], name: "index_dag_runs_on_airflow_accepted"
    t.index ["airflow_accepted"], name: "index_dag_runs_on_airflow_accepted"
    t.index ["dag_status"], name: "index_dag_runs_on_dag_status"
    t.index ["dag_status"], name: "index_dag_runs_on_dag_status"
    t.index ["tanent"], name: "index_dag_runs_on_tanent"
    t.index ["tanent"], name: "index_dag_runs_on_tanent"
    t.index ["user_id"], name: "index_dag_runs_on_user_id"
    t.index ["user_id"], name: "index_dag_runs_on_user_id"
  end


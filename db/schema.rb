# frozen_string_literal: true

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

ActiveRecord::Schema[7.0].define(version: 20_240_221_085_847) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'plpgsql'

  create_table 'active_storage_attachments', force: :cascade do |t|
    t.string 'name', null: false
    t.string 'record_type', null: false
    t.bigint 'blob_id', null: false
    t.datetime 'created_at', null: false
    t.uuid 'record_id', null: false
    t.index ['blob_id'], name: 'index_active_storage_attachments_on_blob_id'
  end

  create_table 'active_storage_blobs', force: :cascade do |t|
    t.string 'key', null: false
    t.string 'filename', null: false
    t.string 'content_type'
    t.text 'metadata'
    t.string 'service_name', null: false
    t.bigint 'byte_size', null: false
    t.string 'checksum'
    t.datetime 'created_at', null: false
    t.index ['key'], name: 'index_active_storage_blobs_on_key', unique: true
  end

  create_table 'active_storage_variant_records', force: :cascade do |t|
    t.bigint 'blob_id', null: false
    t.string 'variation_digest', null: false
    t.index %w[blob_id variation_digest], name: 'index_active_storage_variant_records_uniqueness', unique: true
  end

  create_table 'agent_tools', force: :cascade do |t|
    t.string 'name'
    t.string 'invoke_name'
    t.string 'description'
    t.string 'invoke_description'
    t.string 'category'
    t.jsonb 'meta', default: {}, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['category'], name: 'index_agent_tools_on_category'
  end

  create_table 'agent_use_tools', force: :cascade do |t|
    t.bigint 'assistant_agent_id', null: false
    t.bigint 'agent_tool_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['agent_tool_id'], name: 'index_agent_use_tools_on_agent_tool_id'
    t.index ['assistant_agent_id'], name: 'index_agent_use_tools_on_assistant_agent_id'
  end

  create_table 'api_keys', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'user_id', null: false
    t.string 'key', null: false
    t.datetime 'expires_at'
    t.boolean 'active', default: true
    t.string 'tenant', null: false
    t.string 'name'
    t.string 'description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['key'], name: 'index_api_keys_on_key', unique: true
    t.index ['tenant'], name: 'index_api_keys_on_tenant'
    t.index ['user_id'], name: 'index_api_keys_on_user_id'
  end

  create_table 'assessment_records', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'title'
    t.jsonb 'record'
    t.jsonb 'meta'
    t.string 'recordable_type'
    t.uuid 'recordable_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[recordable_type recordable_id], name: 'index_assessment_records_on_recordable'
  end

  create_table 'assistant_agents', force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.string 'system_message'
    t.string 'subdomain'
    t.jsonb 'llm_config'
    t.jsonb 'meta'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'remark'
    t.string 'version'
    t.string 'name_en'
    t.string 'prompt_header'
    t.string 'category'
    t.string 'helper_agent_system_message'
    t.string 'conclude_conversation_message'
    t.index ['category'], name: 'index_assistant_agents_on_category'
    t.index ['name'], name: 'index_assistant_agents_on_name'
    t.index ['name_en'], name: 'index_assistant_agents_on_name_en'
    t.index ['version'], name: 'index_assistant_agents_on_version'
  end

  create_table 'chatbots', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.uuid 'user_id', null: false
    t.integer 'category', default: 0, null: false
    t.jsonb 'meta', default: {}
    t.jsonb 'source', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'is_public', default: false, null: false
    t.datetime 'expired_at'
    t.integer 'access_count', default: 0
    t.string 'object_type'
    t.uuid 'object_id'
    t.jsonb 'assistive_questions', default: [], null: false
    t.boolean 'has_chatbot_updated', default: false, null: false
    t.integer 'energy_cost', default: 0
    t.index ['category'], name: 'index_chatbots_on_category'
    t.index ['user_id'], name: 'index_chatbots_on_user_id'
  end

  create_table 'classification_model_versions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'model_name', null: false
    t.string 'entity_name', null: false
    t.string 'description', default: ''
    t.uuid 'pervious_version_id'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['entity_name'], name: 'index_classification_model_versions_on_entity_name'
    t.index ['pervious_version_id'], name: 'index_classification_model_versions_on_pervious_version_id'
  end

  create_table 'cors', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.string 'description', default: ''
    t.string 'url', null: false
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end

  create_table 'dag_runs', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'user_id'
    t.string 'dag_name'
    t.integer 'dag_status', default: 0, null: false
    t.jsonb 'meta', default: {}
    t.jsonb 'statistic', default: {}
    t.jsonb 'dag_meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'airflow_accepted', default: false, null: false
    t.index ['airflow_accepted'], name: 'index_dag_runs_on_airflow_accepted'
    t.index ['dag_status'], name: 'index_dag_runs_on_dag_status'
    t.index ['user_id'], name: 'index_dag_runs_on_user_id'
  end

  create_table 'dags', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'user_id'
    t.string 'name'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['user_id'], name: 'index_dags_on_user_id'
  end

  create_table 'departments', force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.jsonb 'meta'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end

  create_table 'document_approvals', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'document_id'
    t.uuid 'form_data_id'
    t.uuid 'approval_user_id'
    t.integer 'approval_status', default: 0, null: false
    t.text 'remark'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.text 'signature'
    t.string 'signature_image_url'
    t.index ['approval_status'], name: 'index_document_approvals_on_approval_status'
    t.index ['approval_user_id'], name: 'index_document_approvals_on_approval_user_id'
    t.index ['document_id'], name: 'index_document_approvals_on_document_id'
    t.index ['form_data_id'], name: 'index_document_approvals_on_form_data_id'
  end

  create_table 'document_smart_extraction_data', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.jsonb 'data'
    t.uuid 'document_id', null: false
    t.uuid 'smart_extraction_schema_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.integer 'status', default: 0
    t.boolean 'is_ready', default: false
    t.integer 'retry_count', default: 0
    t.jsonb 'meta', default: {}
    t.index ['smart_extraction_schema_id'], name: 'index_smart_extraction_data_on_smart_extraction_schema_id'
  end

  create_table 'documents', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'storage_url'
    t.text 'content'
    t.integer 'status', default: 0, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.integer 'approval_status', default: 0, null: false
    t.uuid 'approval_user_id'
    t.datetime 'approval_at'
    t.uuid 'folder_id'
    t.string 'upload_local_path'
    t.uuid 'user_id'
    t.boolean 'is_classified', default: false
    t.boolean 'is_document', default: true
    t.jsonb 'meta', default: {}
    t.boolean 'is_classifier_trained', default: false
    t.boolean 'is_embedded', default: false
    t.text 'error_message'
    t.integer 'retry_count', default: 0
    t.index ['approval_status'], name: 'index_documents_on_approval_status'
    t.index ['approval_user_id'], name: 'index_documents_on_approval_user_id'
    t.index ['folder_id'], name: 'index_documents_on_folder_id'
    t.index ['name'], name: 'index_documents_on_name'
    t.index ['status'], name: 'index_documents_on_status'
    t.index ['upload_local_path'], name: 'index_documents_on_upload_local_path'
    t.index ['user_id'], name: 'index_documents_on_user_id'
  end

  create_table 'energies', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.integer 'value', default: 100
    t.uuid 'user_id', null: false
    t.string 'user_type', null: false
    t.string 'entity_name'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['entity_name'], name: 'index_energies_on_entity_name'
    t.index ['user_id'], name: 'index_energies_on_user_id'
    t.index ['user_type'], name: 'index_energies_on_user_type'
  end

  create_table 'energy_consumption_records', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'marketplace_item_id', null: false
    t.integer 'energy_consumed'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'user_type', null: false
    t.uuid 'user_id', null: false
    t.index ['marketplace_item_id'], name: 'index_energy_consumption_records_on_marketplace_item_id'
    t.index %w[user_type user_id], name: 'index_energy_consumption_records_on_user'
  end

  create_table 'entities', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.string 'description', default: ''
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end

  create_table 'folder_hierarchies', id: false, force: :cascade do |t|
    t.uuid 'ancestor_id', null: false
    t.uuid 'descendant_id', null: false
    t.integer 'generations', null: false
    t.index %w[ancestor_id descendant_id generations], name: 'folder_anc_desc_idx', unique: true
    t.index ['descendant_id'], name: 'folder_desc_idx'
  end

  create_table 'folders', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', default: 'New Folder', null: false
    t.uuid 'parent_id'
    t.uuid 'user_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['parent_id'], name: 'index_folders_on_parent_id'
    t.index ['user_id'], name: 'index_folders_on_user_id'
  end

  create_table 'form_datum', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'document_id'
    t.uuid 'form_schema_id'
    t.jsonb 'data', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['document_id'], name: 'index_form_datum_on_document_id'
    t.index ['form_schema_id'], name: 'index_form_datum_on_form_schema_id'
  end

  create_table 'form_schemas', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.json 'form_schema', default: {}
    t.json 'ui_schema', default: {}
    t.jsonb 'data_schema', default: {}
    t.text 'description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'azure_form_model_id'
    t.boolean 'is_ready', default: false, null: false
    t.jsonb 'form_fields', default: []
    t.jsonb 'form_projection', default: []
    t.boolean 'can_project', default: false, null: false
    t.string 'projection_image_url', default: ''
    t.uuid 'label_id'
    t.index ['name'], name: 'index_form_schemas_on_name'
  end

  create_table 'functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'title', default: '', null: false
  end

  create_table 'general_users', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'email'
    t.string 'encrypted_password'
    t.string 'reset_password_token'
    t.datetime 'reset_password_sent_at'
    t.datetime 'remember_created_at'
    t.string 'nickname'
    t.string 'phone'
    t.date 'date_of_birth'
    t.integer 'sex'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['email'], name: 'index_general_users_on_email', unique: true
  end

  create_table 'identities', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'user_id', null: false
    t.string 'provider'
    t.string 'uid'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['provider'], name: 'index_identities_on_provider'
    t.index ['user_id'], name: 'index_identities_on_user_id'
  end

  create_table 'jwt_denylist', force: :cascade do |t|
    t.string 'jti', null: false
    t.datetime 'exp', null: false
    t.index ['jti'], name: 'index_jwt_denylist_on_jti'
  end

  create_table 'log_messages', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'chatbot_id', null: false
    t.uuid 'session_id', null: false
    t.text 'content', default: '', null: false
    t.string 'role'
    t.uuid 'previous_message_id'
    t.boolean 'has_chat_history', default: false
    t.jsonb 'meta', default: {}, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['chatbot_id'], name: 'index_log_messages_on_chatbot_id'
    t.index ['session_id'], name: 'index_log_messages_on_session_id'
  end

  create_table 'marketplace_items', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'chatbot_id'
    t.uuid 'user_id'
    t.string 'entity_name', null: false
    t.string 'chatbot_name', null: false
    t.string 'chatbot_description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['entity_name'], name: 'index_marketplace_items_on_entity_name'
  end

  create_table 'messages', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'chatbot_id', null: false
    t.text 'content', null: false
    t.string 'role', default: 'user', null: false
    t.uuid 'user_id'
    t.string 'object_type', null: false
    t.boolean 'is_read', default: false, null: false
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['chatbot_id'], name: 'index_messages_on_chatbot_id'
    t.index ['object_type'], name: 'index_messages_on_object_type'
    t.index ['user_id'], name: 'index_messages_on_user_id'
  end

  create_table 'mini_apps', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.jsonb 'meta', default: {}
    t.uuid 'user_id', null: false
    t.uuid 'folder_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['folder_id'], name: 'index_mini_apps_on_folder_id'
    t.index ['user_id'], name: 'index_mini_apps_on_user_id'
  end

  create_table 'pdf_page_details', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'document_id', null: false
    t.integer 'page_number'
    t.text 'summary'
    t.string 'keywords'
    t.integer 'status', default: 0, null: false
    t.integer 'retry_count', default: 0, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.text 'error_message'
    t.index ['document_id'], name: 'index_pdf_page_details_on_document_id'
  end

  create_table 'project_tasks', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'title', default: 'New Project Task', null: false
    t.text 'description'
    t.uuid 'project_id', null: false
    t.uuid 'user_id', null: false
    t.boolean 'is_completed', default: false, null: false
    t.integer 'order', default: 0, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.datetime 'deadline_at', precision: nil
    t.index ['project_id'], name: 'index_project_tasks_on_project_id'
    t.index ['user_id'], name: 'index_project_tasks_on_user_id'
  end

  create_table 'project_workflow_steps', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.integer 'position'
    t.string 'name', null: false
    t.string 'description'
    t.uuid 'user_id'
    t.uuid 'project_workflow_id'
    t.integer 'status', default: 0
    t.boolean 'is_human', default: true
    t.jsonb 'meta', default: {}
    t.jsonb 'dag_meta', default: {}
    t.datetime 'deadline'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.uuid 'assignee_id'
    t.index ['project_workflow_id'], name: 'index_project_workflow_steps_on_project_workflow_id'
    t.index ['status'], name: 'index_project_workflow_steps_on_status'
    t.index ['user_id'], name: 'index_project_workflow_steps_on_user_id'
  end

  create_table 'project_workflows', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.integer 'status', default: 0, null: false
    t.string 'description'
    t.uuid 'user_id'
    t.boolean 'is_process_workflow', default: false
    t.datetime 'deadline'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.uuid 'folder_id'
    t.boolean 'is_template', default: false, null: false
    t.uuid 'source_workflow_id'
    t.index ['folder_id'], name: 'index_project_workflows_on_folder_id'
    t.index ['is_process_workflow'], name: 'index_project_workflows_on_is_process_workflow'
    t.index ['source_workflow_id'], name: 'index_project_workflows_on_source_workflow_id'
    t.index ['status'], name: 'index_project_workflows_on_status'
  end

  create_table 'projects', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', default: 'New Project', null: false
    t.string 'description'
    t.uuid 'user_id', null: false
    t.uuid 'folder_id', null: false
    t.boolean 'is_public', default: false
    t.boolean 'is_finished', default: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.datetime 'deadline_at', precision: nil
  end

  create_table 'roles', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'resource_type'
    t.uuid 'resource_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[name resource_type resource_id], name: 'index_roles_on_name_and_resource_type_and_resource_id'
    t.index %w[resource_type resource_id], name: 'index_roles_on_resource'
  end

  create_table 'smart_extraction_schemas', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.string 'description'
    t.uuid 'label_id'
    t.jsonb 'schema', default: {}
    t.jsonb 'data_schema', default: {}
    t.uuid 'user_id'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'has_label', default: false, null: false
    t.index ['label_id'], name: 'index_smart_extraction_schemas_on_label_id'
    t.index ['user_id'], name: 'index_smart_extraction_schemas_on_user_id'
  end

  create_table 'storyboard_item_associations', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'storyboard_id', null: false
    t.uuid 'storyboard_item_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['storyboard_id'], name: 'index_storyboard_item_associations_on_storyboard_id'
    t.index ['storyboard_item_id'], name: 'index_storyboard_item_associations_on_storyboard_item_id'
  end

  create_table 'storyboard_items', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.text 'description'
    t.uuid 'user_id', null: false
    t.string 'query', null: false
    t.text 'data', default: ''
    t.text 'sql', default: ''
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'is_ready', default: false, null: false
    t.integer 'status', default: 0, null: false
    t.string 'object_type', null: false
    t.uuid 'object_id', null: false
    t.string 'item_type'
    t.index ['user_id'], name: 'index_storyboard_items_on_user_id'
  end

  create_table 'storyboards', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'title', null: false
    t.text 'description'
    t.uuid 'user_id', null: false
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['user_id'], name: 'index_storyboards_on_user_id'
  end

  create_table 'super_admins', force: :cascade do |t|
    t.string 'email', default: '', null: false
    t.string 'encrypted_password', default: '', null: false
    t.string 'reset_password_token'
    t.datetime 'reset_password_sent_at'
    t.datetime 'remember_created_at'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['email'], name: 'index_super_admins_on_email', unique: true
    t.index ['reset_password_token'], name: 'index_super_admins_on_reset_password_token', unique: true
  end

  create_table 'tag_functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'tag_id', null: false
    t.uuid 'function_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['function_id'], name: 'index_tag_functions_on_function_id'
    t.index ['tag_id'], name: 'index_tag_functions_on_tag_id'
  end

  create_table 'taggings', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'tag_id'
    t.string 'taggable_type'
    t.uuid 'taggable_id'
    t.string 'tagger_type'
    t.uuid 'tagger_id'
    t.string 'context', limit: 128
    t.datetime 'created_at', precision: nil
    t.string 'tenant', limit: 128
    t.index ['context'], name: 'index_taggings_on_context'
    t.index %w[tag_id taggable_id taggable_type context tagger_id tagger_type], name: 'taggings_idx',
                                                                                unique: true
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index %w[taggable_id taggable_type context], name: 'taggings_taggable_context_idx'
    t.index %w[taggable_id taggable_type tagger_id context], name: 'taggings_idy'
    t.index ['taggable_id'], name: 'index_taggings_on_taggable_id'
    t.index %w[taggable_type taggable_id], name: 'index_taggings_on_taggable_type_and_taggable_id'
    t.index ['taggable_type'], name: 'index_taggings_on_taggable_type'
    t.index %w[tagger_id tagger_type], name: 'index_taggings_on_tagger_id_and_tagger_type'
    t.index ['tagger_id'], name: 'index_taggings_on_tagger_id'
    t.index %w[tagger_type tagger_id], name: 'index_taggings_on_tagger_type_and_tagger_id'
    t.index ['tenant'], name: 'index_taggings_on_tenant'
  end

  create_table 'tags', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.integer 'taggings_count', default: 0
    t.boolean 'is_checked', default: false
    t.uuid 'folder_id'
    t.uuid 'user_id'
    t.jsonb 'meta', default: {}
    t.integer 'smart_extraction_schemas_count', default: 0
    t.index ['name'], name: 'index_tags_on_name', unique: true
  end

  create_table 'user_mailboxes', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'user_id', null: false
    t.uuid 'document_id', null: false
    t.string 'message_id'
    t.string 'subject'
    t.string 'sender'
    t.string 'recipient'
    t.datetime 'sent_at'
    t.datetime 'received_at'
    t.jsonb 'attachment'
    t.text 'content'
    t.boolean 'read', default: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['document_id'], name: 'index_user_mailboxes_on_document_id'
    t.index ['user_id'], name: 'index_user_mailboxes_on_user_id'
  end

  create_table 'users', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'email', default: '', null: false
    t.string 'encrypted_password', default: '', null: false
    t.string 'reset_password_token'
    t.datetime 'reset_password_sent_at'
    t.datetime 'remember_created_at'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'nickname'
    t.string 'phone'
    t.string 'position'
    t.date 'date_of_birth'
    t.integer 'sex'
    t.jsonb 'profile'
    t.integer 'failed_attempts', default: 0, null: false
    t.string 'unlock_token'
    t.datetime 'locked_at'
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
    t.index ['unlock_token'], name: 'index_users_on_unlock_token', unique: true
  end

  create_table 'users_roles', id: false, force: :cascade do |t|
    t.uuid 'user_id'
    t.uuid 'role_id'
    t.index ['role_id'], name: 'index_users_roles_on_role_id'
    t.index %w[user_id role_id], name: 'index_users_roles_on_user_id_and_role_id'
    t.index ['user_id'], name: 'index_users_roles_on_user_id'
  end

  create_table 'versions', force: :cascade do |t|
    t.string 'item_type', null: false
    t.string 'item_id', null: false
    t.string 'event', null: false
    t.string 'whodunnit'
    t.text 'object'
    t.datetime 'created_at'
    t.index %w[item_type item_id], name: 'index_versions_on_item_type_and_item_id'
  end

  add_foreign_key 'active_storage_attachments', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_variant_records', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'agent_use_tools', 'agent_tools'
  add_foreign_key 'agent_use_tools', 'assistant_agents'
  add_foreign_key 'dag_runs', 'users'
  add_foreign_key 'dags', 'users'
  add_foreign_key 'documents', 'folders'
  add_foreign_key 'folders', 'users'
  add_foreign_key 'identities', 'users'
  add_foreign_key 'messages', 'chatbots'
  add_foreign_key 'messages', 'users'
  add_foreign_key 'mini_apps', 'folders'
  add_foreign_key 'mini_apps', 'users'
  add_foreign_key 'pdf_page_details', 'documents'
  add_foreign_key 'project_workflow_steps', 'project_workflows'
  add_foreign_key 'project_workflow_steps', 'users'
  add_foreign_key 'project_workflows', 'folders'
  add_foreign_key 'projects', 'folders'
  add_foreign_key 'projects', 'users'
  add_foreign_key 'storyboard_item_associations', 'storyboard_items'
  add_foreign_key 'storyboard_item_associations', 'storyboards'
  add_foreign_key 'storyboard_items', 'users'
  add_foreign_key 'storyboards', 'users'
  add_foreign_key 'taggings', 'tags'
  add_foreign_key 'user_mailboxes', 'documents'
  add_foreign_key 'user_mailboxes', 'users'
end

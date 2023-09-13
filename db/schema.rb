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

ActiveRecord::Schema[7.0].define(version: 20_230_913_111_912) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'plpgsql'

  create_table 'active_storage_attachments', force: :cascade do |t|
    t.string 'name', null: false
    t.string 'record_type', null: false
    t.bigint 'blob_id', null: false
    t.datetime 'created_at', null: false
    t.uuid 'record_id', null: false
    t.index ['blob_id'], name: 'index_active_storage_attachments_on_blob_id'
    t.index ['blob_id'], name: 'index_active_storage_attachments_on_blob_id'
  end

  create_table 'active_storage_attachments', force: :cascade do |t|
    t.string 'name', null: false
    t.string 'record_type', null: false
    t.bigint 'blob_id', null: false
    t.datetime 'created_at', null: false
    t.uuid 'record_id', null: false
    t.index ['blob_id'], name: 'index_active_storage_attachments_on_blob_id'
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
    t.index ['key'], name: 'index_active_storage_blobs_on_key', unique: true
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
    t.index ['key'], name: 'index_active_storage_blobs_on_key', unique: true
  end

  create_table 'active_storage_variant_records', force: :cascade do |t|
    t.bigint 'blob_id', null: false
    t.string 'variation_digest', null: false
    t.index %w[blob_id variation_digest], name: 'index_active_storage_variant_records_uniqueness', unique: true
    t.index %w[blob_id variation_digest], name: 'index_active_storage_variant_records_uniqueness', unique: true
  end

  create_table 'active_storage_variant_records', force: :cascade do |t|
    t.bigint 'blob_id', null: false
    t.string 'variation_digest', null: false
    t.index %w[blob_id variation_digest], name: 'index_active_storage_variant_records_uniqueness', unique: true
    t.index %w[blob_id variation_digest], name: 'index_active_storage_variant_records_uniqueness', unique: true
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
    t.index ['category'], name: 'index_chatbots_on_category'
    t.index ['category'], name: 'index_chatbots_on_category'
    t.index ['user_id'], name: 'index_chatbots_on_user_id'
    t.index ['user_id'], name: 'index_chatbots_on_user_id'
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
    t.index ['category'], name: 'index_chatbots_on_category'
    t.index ['category'], name: 'index_chatbots_on_category'
    t.index ['user_id'], name: 'index_chatbots_on_user_id'
    t.index ['user_id'], name: 'index_chatbots_on_user_id'
  end

  create_table 'departments', force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.jsonb 'meta'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
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
    t.index ['approval_status'], name: 'index_document_approvals_on_approval_status'
    t.index ['approval_user_id'], name: 'index_document_approvals_on_approval_user_id'
    t.index ['approval_user_id'], name: 'index_document_approvals_on_approval_user_id'
    t.index ['document_id'], name: 'index_document_approvals_on_document_id'
    t.index ['document_id'], name: 'index_document_approvals_on_document_id'
    t.index ['form_data_id'], name: 'index_document_approvals_on_form_data_id'
    t.index ['form_data_id'], name: 'index_document_approvals_on_form_data_id'
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
    t.index ['approval_status'], name: 'index_document_approvals_on_approval_status'
    t.index ['approval_user_id'], name: 'index_document_approvals_on_approval_user_id'
    t.index ['approval_user_id'], name: 'index_document_approvals_on_approval_user_id'
    t.index ['document_id'], name: 'index_document_approvals_on_document_id'
    t.index ['document_id'], name: 'index_document_approvals_on_document_id'
    t.index ['form_data_id'], name: 'index_document_approvals_on_form_data_id'
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
    t.index ['smart_extraction_schema_id'], name: 'index_smart_extraction_data_on_smart_extraction_schema_id'
    t.index ['smart_extraction_schema_id'], name: 'index_smart_extraction_data_on_smart_extraction_schema_id'
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
    t.index ['smart_extraction_schema_id'], name: 'index_smart_extraction_data_on_smart_extraction_schema_id'
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
    t.index ['approval_status'], name: 'index_documents_on_approval_status'
    t.index ['approval_user_id'], name: 'index_documents_on_approval_user_id'
    t.index ['approval_user_id'], name: 'index_documents_on_approval_user_id'
    t.index ['folder_id'], name: 'index_documents_on_folder_id'
    t.index ['folder_id'], name: 'index_documents_on_folder_id'
    t.index ['name'], name: 'index_documents_on_name'
    t.index ['name'], name: 'index_documents_on_name'
    t.index ['status'], name: 'index_documents_on_status'
    t.index ['status'], name: 'index_documents_on_status'
    t.index ['upload_local_path'], name: 'index_documents_on_upload_local_path'
    t.index ['upload_local_path'], name: 'index_documents_on_upload_local_path'
    t.index ['user_id'], name: 'index_documents_on_user_id'
    t.index ['user_id'], name: 'index_documents_on_user_id'
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
    t.index ['approval_status'], name: 'index_documents_on_approval_status'
    t.index ['approval_user_id'], name: 'index_documents_on_approval_user_id'
    t.index ['approval_user_id'], name: 'index_documents_on_approval_user_id'
    t.index ['folder_id'], name: 'index_documents_on_folder_id'
    t.index ['folder_id'], name: 'index_documents_on_folder_id'
    t.index ['name'], name: 'index_documents_on_name'
    t.index ['name'], name: 'index_documents_on_name'
    t.index ['status'], name: 'index_documents_on_status'
    t.index ['status'], name: 'index_documents_on_status'
    t.index ['upload_local_path'], name: 'index_documents_on_upload_local_path'
    t.index ['upload_local_path'], name: 'index_documents_on_upload_local_path'
    t.index ['user_id'], name: 'index_documents_on_user_id'
    t.index ['user_id'], name: 'index_documents_on_user_id'
  end

  create_table 'folder_hierarchies', id: false, force: :cascade do |t|
    t.uuid 'ancestor_id', null: false
    t.uuid 'descendant_id', null: false
    t.integer 'generations', null: false
    t.index %w[ancestor_id descendant_id generations], name: 'folder_anc_desc_idx', unique: true
    t.index %w[ancestor_id descendant_id generations], name: 'folder_anc_desc_idx', unique: true
    t.index ['descendant_id'], name: 'folder_desc_idx'
    t.index ['descendant_id'], name: 'folder_desc_idx'
  end

  create_table 'folder_hierarchies', id: false, force: :cascade do |t|
    t.uuid 'ancestor_id', null: false
    t.uuid 'descendant_id', null: false
    t.integer 'generations', null: false
    t.index %w[ancestor_id descendant_id generations], name: 'folder_anc_desc_idx', unique: true
    t.index %w[ancestor_id descendant_id generations], name: 'folder_anc_desc_idx', unique: true
    t.index ['descendant_id'], name: 'folder_desc_idx'
    t.index ['descendant_id'], name: 'folder_desc_idx'
  end

  create_table 'folders', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', default: 'New Folder', null: false
    t.uuid 'parent_id'
    t.uuid 'user_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['parent_id'], name: 'index_folders_on_parent_id'
    t.index ['parent_id'], name: 'index_folders_on_parent_id'
    t.index ['user_id'], name: 'index_folders_on_user_id'
    t.index ['user_id'], name: 'index_folders_on_user_id'
  end

  create_table 'folders', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', default: 'New Folder', null: false
    t.uuid 'parent_id'
    t.uuid 'user_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['parent_id'], name: 'index_folders_on_parent_id'
    t.index ['parent_id'], name: 'index_folders_on_parent_id'
    t.index ['user_id'], name: 'index_folders_on_user_id'
    t.index ['user_id'], name: 'index_folders_on_user_id'
  end

  create_table 'form_datum', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'document_id'
    t.uuid 'form_schema_id'
    t.jsonb 'data', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['document_id'], name: 'index_form_datum_on_document_id'
    t.index ['document_id'], name: 'index_form_datum_on_document_id'
    t.index ['form_schema_id'], name: 'index_form_datum_on_form_schema_id'
    t.index ['form_schema_id'], name: 'index_form_datum_on_form_schema_id'
  end

  create_table 'form_datum', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'document_id'
    t.uuid 'form_schema_id'
    t.jsonb 'data', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['document_id'], name: 'index_form_datum_on_document_id'
    t.index ['document_id'], name: 'index_form_datum_on_document_id'
    t.index ['form_schema_id'], name: 'index_form_datum_on_form_schema_id'
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
    t.index ['name'], name: 'index_form_schemas_on_name'
    t.index ['name'], name: 'index_form_schemas_on_name'
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
    t.index ['name'], name: 'index_form_schemas_on_name'
    t.index ['name'], name: 'index_form_schemas_on_name'
  end

  create_table 'functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'title', default: '', null: false
  end

  create_table 'functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'description'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'title', default: '', null: false
  end

  create_table 'jwt_denylist', force: :cascade do |t|
    t.string 'jti', null: false
    t.datetime 'exp', null: false
    t.index ['jti'], name: 'index_jwt_denylist_on_jti'
    t.index ['jti'], name: 'index_jwt_denylist_on_jti'
  end

  create_table 'jwt_denylist', force: :cascade do |t|
    t.string 'jti', null: false
    t.datetime 'exp', null: false
    t.index ['jti'], name: 'index_jwt_denylist_on_jti'
    t.index ['jti'], name: 'index_jwt_denylist_on_jti'
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
    t.index ['folder_id'], name: 'index_mini_apps_on_folder_id'
    t.index ['user_id'], name: 'index_mini_apps_on_user_id'
    t.index ['user_id'], name: 'index_mini_apps_on_user_id'
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
    t.index ['folder_id'], name: 'index_mini_apps_on_folder_id'
    t.index ['user_id'], name: 'index_mini_apps_on_user_id'
    t.index ['user_id'], name: 'index_mini_apps_on_user_id'
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
    t.index ['project_id'], name: 'index_project_tasks_on_project_id'
    t.index ['user_id'], name: 'index_project_tasks_on_user_id'
    t.index ['user_id'], name: 'index_project_tasks_on_user_id'
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
    t.index ['project_id'], name: 'index_project_tasks_on_project_id'
    t.index ['user_id'], name: 'index_project_tasks_on_user_id'
    t.index ['user_id'], name: 'index_project_tasks_on_user_id'
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
    t.index %w[name resource_type resource_id], name: 'index_roles_on_name_and_resource_type_and_resource_id'
    t.index %w[resource_type resource_id], name: 'index_roles_on_resource'
    t.index %w[resource_type resource_id], name: 'index_roles_on_resource'
  end

  create_table 'roles', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name'
    t.string 'resource_type'
    t.uuid 'resource_id'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[name resource_type resource_id], name: 'index_roles_on_name_and_resource_type_and_resource_id'
    t.index %w[name resource_type resource_id], name: 'index_roles_on_name_and_resource_type_and_resource_id'
    t.index %w[resource_type resource_id], name: 'index_roles_on_resource'
    t.index %w[resource_type resource_id], name: 'index_roles_on_resource'
  end

  create_table 'smart_extraction_schemas', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.string 'description'
    t.uuid 'label_id', null: false
    t.jsonb 'schema', default: {}
    t.jsonb 'data_schema', default: {}
    t.uuid 'user_id'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['label_id'], name: 'index_smart_extraction_schemas_on_label_id'
    t.index ['label_id'], name: 'index_smart_extraction_schemas_on_label_id'
    t.index ['user_id'], name: 'index_smart_extraction_schemas_on_user_id'
    t.index ['user_id'], name: 'index_smart_extraction_schemas_on_user_id'
  end

  create_table 'smart_extraction_schemas', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.string 'name', null: false
    t.string 'description'
    t.uuid 'label_id', null: false
    t.jsonb 'schema', default: {}
    t.jsonb 'data_schema', default: {}
    t.uuid 'user_id'
    t.jsonb 'meta', default: {}
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['label_id'], name: 'index_smart_extraction_schemas_on_label_id'
    t.index ['label_id'], name: 'index_smart_extraction_schemas_on_label_id'
    t.index ['user_id'], name: 'index_smart_extraction_schemas_on_user_id'
    t.index ['user_id'], name: 'index_smart_extraction_schemas_on_user_id'
  end

  create_table 'tag_functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'tag_id', null: false
    t.uuid 'function_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['function_id'], name: 'index_tag_functions_on_function_id'
    t.index ['function_id'], name: 'index_tag_functions_on_function_id'
    t.index ['tag_id'], name: 'index_tag_functions_on_tag_id'
    t.index ['tag_id'], name: 'index_tag_functions_on_tag_id'
  end

  create_table 'tag_functions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
    t.uuid 'tag_id', null: false
    t.uuid 'function_id', null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['function_id'], name: 'index_tag_functions_on_function_id'
    t.index ['function_id'], name: 'index_tag_functions_on_function_id'
    t.index ['tag_id'], name: 'index_tag_functions_on_tag_id'
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
    t.index ['context'], name: 'index_taggings_on_context'
    t.index %w[tag_id taggable_id taggable_type context tagger_id tagger_type], name: 'taggings_idx',
                                                                                unique: true
    t.index %w[tag_id taggable_id taggable_type context tagger_id tagger_type], name: 'taggings_idx',
                                                                                unique: true
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index %w[taggable_id taggable_type context], name: 'taggings_taggable_context_idx'
    t.index %w[taggable_id taggable_type context], name: 'taggings_taggable_context_idx'
    t.index %w[taggable_id taggable_type tagger_id context], name: 'taggings_idy'
    t.index %w[taggable_id taggable_type tagger_id context], name: 'taggings_idy'
    t.index ['taggable_id'], name: 'index_taggings_on_taggable_id'
    t.index ['taggable_id'], name: 'index_taggings_on_taggable_id'
    t.index %w[taggable_type taggable_id], name: 'index_taggings_on_taggable_type_and_taggable_id'
    t.index %w[taggable_type taggable_id], name: 'index_taggings_on_taggable_type_and_taggable_id'
    t.index ['taggable_type'], name: 'index_taggings_on_taggable_type'
    t.index ['taggable_type'], name: 'index_taggings_on_taggable_type'
    t.index %w[tagger_id tagger_type], name: 'index_taggings_on_tagger_id_and_tagger_type'
    t.index %w[tagger_id tagger_type], name: 'index_taggings_on_tagger_id_and_tagger_type'
    t.index ['tagger_id'], name: 'index_taggings_on_tagger_id'
    t.index ['tagger_id'], name: 'index_taggings_on_tagger_id'
    t.index %w[tagger_type tagger_id], name: 'index_taggings_on_tagger_type_and_tagger_id'
    t.index %w[tagger_type tagger_id], name: 'index_taggings_on_tagger_type_and_tagger_id'
    t.index ['tenant'], name: 'index_taggings_on_tenant'
    t.index ['tenant'], name: 'index_taggings_on_tenant'
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
    t.index ['context'], name: 'index_taggings_on_context'
    t.index %w[tag_id taggable_id taggable_type context tagger_id tagger_type], name: 'taggings_idx',
                                                                                unique: true
    t.index %w[tag_id taggable_id taggable_type context tagger_id tagger_type], name: 'taggings_idx',
                                                                                unique: true
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index %w[taggable_id taggable_type context], name: 'taggings_taggable_context_idx'
    t.index %w[taggable_id taggable_type context], name: 'taggings_taggable_context_idx'
    t.index %w[taggable_id taggable_type tagger_id context], name: 'taggings_idy'
    t.index %w[taggable_id taggable_type tagger_id context], name: 'taggings_idy'
    t.index ['taggable_id'], name: 'index_taggings_on_taggable_id'
    t.index ['taggable_id'], name: 'index_taggings_on_taggable_id'
    t.index %w[taggable_type taggable_id], name: 'index_taggings_on_taggable_type_and_taggable_id'
    t.index %w[taggable_type taggable_id], name: 'index_taggings_on_taggable_type_and_taggable_id'
    t.index ['taggable_type'], name: 'index_taggings_on_taggable_type'
    t.index ['taggable_type'], name: 'index_taggings_on_taggable_type'
    t.index %w[tagger_id tagger_type], name: 'index_taggings_on_tagger_id_and_tagger_type'
    t.index %w[tagger_id tagger_type], name: 'index_taggings_on_tagger_id_and_tagger_type'
    t.index ['tagger_id'], name: 'index_taggings_on_tagger_id'
    t.index ['tagger_id'], name: 'index_taggings_on_tagger_id'
    t.index %w[tagger_type tagger_id], name: 'index_taggings_on_tagger_type_and_tagger_id'
    t.index %w[tagger_type tagger_id], name: 'index_taggings_on_tagger_type_and_tagger_id'
    t.index ['tenant'], name: 'index_taggings_on_tenant'
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
    t.index ['name'], name: 'index_tags_on_name', unique: true
    t.index ['name'], name: 'index_tags_on_name', unique: true
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
    t.index ['name'], name: 'index_tags_on_name', unique: true
    t.index ['name'], name: 'index_tags_on_name', unique: true
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
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
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
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
    t.index ['reset_password_token'], name: 'index_users_on_reset_password_token', unique: true
  end

  create_table 'users_roles', id: false, force: :cascade do |t|
    t.uuid 'user_id'
    t.uuid 'role_id'
    t.index ['role_id'], name: 'index_users_roles_on_role_id'
    t.index ['role_id'], name: 'index_users_roles_on_role_id'
    t.index %w[user_id role_id], name: 'index_users_roles_on_user_id_and_role_id'
    t.index %w[user_id role_id], name: 'index_users_roles_on_user_id_and_role_id'
    t.index ['user_id'], name: 'index_users_roles_on_user_id'
    t.index ['user_id'], name: 'index_users_roles_on_user_id'
  end

  create_table 'users_roles', id: false, force: :cascade do |t|
    t.uuid 'user_id'
    t.uuid 'role_id'
    t.index ['role_id'], name: 'index_users_roles_on_role_id'
    t.index ['role_id'], name: 'index_users_roles_on_role_id'
    t.index %w[user_id role_id], name: 'index_users_roles_on_user_id_and_role_id'
    t.index %w[user_id role_id], name: 'index_users_roles_on_user_id_and_role_id'
    t.index ['user_id'], name: 'index_users_roles_on_user_id'
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
    t.index %w[item_type item_id], name: 'index_versions_on_item_type_and_item_id'
  end

  create_table 'versions', force: :cascade do |t|
    t.string 'item_type', null: false
    t.string 'item_id', null: false
    t.string 'event', null: false
    t.string 'whodunnit'
    t.text 'object'
    t.datetime 'created_at'
    t.index %w[item_type item_id], name: 'index_versions_on_item_type_and_item_id'
    t.index %w[item_type item_id], name: 'index_versions_on_item_type_and_item_id'
  end

  add_foreign_key 'active_storage_attachments', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_attachments', 'public.active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_attachments', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_attachments', 'public.active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_variant_records', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_variant_records', 'public.active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_variant_records', 'active_storage_blobs', column: 'blob_id'
  add_foreign_key 'active_storage_variant_records', 'public.active_storage_blobs', column: 'blob_id'
  add_foreign_key 'documents', 'folders'
  add_foreign_key 'documents', 'public.folders', column: 'folder_id'
  add_foreign_key 'documents', 'folders'
  add_foreign_key 'documents', 'public.folders', column: 'folder_id'
  add_foreign_key 'folders', 'public.users', column: 'user_id'
  add_foreign_key 'folders', 'users'
  add_foreign_key 'folders', 'public.users', column: 'user_id'
  add_foreign_key 'folders', 'users'
  add_foreign_key 'mini_apps', 'folders'
  add_foreign_key 'mini_apps', 'public.folders', column: 'folder_id'
  add_foreign_key 'mini_apps', 'public.users', column: 'user_id'
  add_foreign_key 'mini_apps', 'users'
  add_foreign_key 'mini_apps', 'folders'
  add_foreign_key 'mini_apps', 'public.folders', column: 'folder_id'
  add_foreign_key 'mini_apps', 'public.users', column: 'user_id'
  add_foreign_key 'mini_apps', 'users'
  add_foreign_key 'projects', 'folders'
  add_foreign_key 'projects', 'public.folders', column: 'folder_id'
  add_foreign_key 'projects', 'public.users', column: 'user_id'
  add_foreign_key 'projects', 'users'
  add_foreign_key 'projects', 'folders'
  add_foreign_key 'projects', 'public.folders', column: 'folder_id'
  add_foreign_key 'projects', 'public.users', column: 'user_id'
  add_foreign_key 'projects', 'users'
  add_foreign_key 'taggings', 'public.tags', column: 'tag_id'
  add_foreign_key 'taggings', 'tags'
  add_foreign_key 'taggings', 'public.tags', column: 'tag_id'
  add_foreign_key 'taggings', 'tags'
end

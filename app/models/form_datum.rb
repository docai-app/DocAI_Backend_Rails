# frozen_string_literal: true

# == Schema Information
#
# Table name: form_datum
#
#  id             :uuid             not null, primary key
#  document_id    :uuid
#  form_schema_id :uuid
#  data           :jsonb
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_form_datum_on_document_id     (document_id)
#  index_form_datum_on_document_id     (document_id)
#  index_form_datum_on_form_schema_id  (form_schema_id)
#  index_form_datum_on_form_schema_id  (form_schema_id)
#
class FormDatum < ApplicationRecord
  self.table_name = 'form_datum'
  belongs_to :form_schema, optional: true, class_name: 'FormSchema', foreign_key: 'form_schema_id'
  belongs_to :document, optional: true, class_name: 'Document', foreign_key: 'document_id'
  # has_one :document, class_name: "Document", foreign_key: "document_id"
  # has_one :form_schema, class_name: "FormSchema", foreign_key: "form_schema_id"
end

class FormDatum < ApplicationRecord
    belongs_to :form_schema, optional: true, class_name: "FormSchema", foreign_key: "form_schema_id"
    belongs_to :document, optional: true, class_name: "Document", foreign_key: "document_id"
end

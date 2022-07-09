class DocumentApproval < ApplicationRecord
  belongs_to :document, optional: true, class_name: "Document", foreign_key: "document_id"
  belongs_to :form_data, optional: true, class_name: "FormData", foreign_key: "form_data_id"
  belongs_to :approval_user, optional: true, class_name: "User", foreign_key: "approval_user_id"

  enum status: [:awaiting, :approved, :rejected]
end

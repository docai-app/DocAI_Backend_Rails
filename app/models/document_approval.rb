# == Schema Information
#
# Table name: document_approvals
#
#  id               :uuid             not null, primary key
#  document_id      :uuid
#  form_data_id     :uuid
#  approval_user_id :uuid
#  approval_status  :integer          default("awaiting"), not null
#  remark           :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class DocumentApproval < ApplicationRecord
  belongs_to :document, optional: true, class_name: "Document", foreign_key: "document_id"
  belongs_to :form_data, optional: true, class_name: "FormDatum", foreign_key: "form_data_id"
  belongs_to :approval_user, optional: true, class_name: "User", foreign_key: "approval_user_id"

  enum approval_status: [:awaiting, :approved, :rejected]
end

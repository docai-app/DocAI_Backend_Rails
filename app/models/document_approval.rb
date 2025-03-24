# frozen_string_literal: true

# == Schema Information
#
# Table name: document_approvals
#
#  id                  :uuid             not null, primary key
#  document_id         :uuid
#  form_data_id        :uuid
#  approval_user_id    :uuid
#  approval_status     :integer          default("awaiting"), not null
#  remark              :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  signature           :text
#  signature_image_url :string
#
# Indexes
#
#  index_document_approvals_on_approval_status   (approval_status)
#  index_document_approvals_on_approval_user_id  (approval_user_id)
#  index_document_approvals_on_document_id       (document_id)
#  index_document_approvals_on_form_data_id      (form_data_id)
#
class DocumentApproval < ApplicationRecord
  belongs_to :document, optional: true, class_name: 'Document', foreign_key: 'document_id', dependent: :destroy
  belongs_to :form_data, optional: true, class_name: 'FormDatum', foreign_key: 'form_data_id'
  belongs_to :approval_user, optional: true, class_name: 'User', foreign_key: 'approval_user_id'

  enum approval_status: %i[awaiting approved rejected]
end

# frozen_string_literal: true

class SetFormDataIdIsNullOnDocumentApproval < ActiveRecord::Migration[7.0]
  def change
    change_column_null :document_approvals, :form_data_id, true
    change_column_default :document_approvals, :form_data_id, nil
  end
end

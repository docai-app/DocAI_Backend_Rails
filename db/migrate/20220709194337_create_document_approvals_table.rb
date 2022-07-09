class CreateDocumentApprovalsTable < ActiveRecord::Migration[7.0]
  def change
    create_table :document_approvals, id: :uuid do |t|
      t.uuid :document_id
      t.uuid :form_data_id
      t.uuid :approval_user_id
      t.string :approval_status, :integer, null: false, default: 0
      t.timestamps
    end
    add_index :document_approvals, :document_id
    add_index :document_approvals, :form_data_id
    add_index :document_approvals, :approval_user_id
    add_index :document_approvals, :approval_status
  end
end

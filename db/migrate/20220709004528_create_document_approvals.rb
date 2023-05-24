# frozen_string_literal: true

class CreateDocumentApprovals < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :approval_status, :integer, null: false, default: 0
    add_column :documents, :approval_user_id, :uuid
    add_column :documents, :approval_at, :datetime
    add_index :documents, :approval_status
    add_index :documents, :approval_user_id
  end
end

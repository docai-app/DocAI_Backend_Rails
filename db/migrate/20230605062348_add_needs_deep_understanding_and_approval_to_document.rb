class AddNeedsDeepUnderstandingAndApprovalToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :meta, :jsonb, default: {}
  end
end

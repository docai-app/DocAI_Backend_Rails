class AddErrorHandlingToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :error_message, :text, null: true, default: nil
    add_column :documents, :retry_count, :integer, default: 0
  end
end

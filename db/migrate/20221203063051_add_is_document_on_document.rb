class AddIsDocumentOnDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :is_document, :boolean, default: true
  end
end

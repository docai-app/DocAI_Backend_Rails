class AddNeedsDeepUnderstandingToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :needs_deep_understanding, :boolean, default: false, null: false
    add_column :documents, :is_deep_understanding, :boolean, default: false, null: false
  end
end

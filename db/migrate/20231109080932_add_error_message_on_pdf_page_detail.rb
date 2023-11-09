# frozen_string_literal: true

class AddErrorMessageOnPdfPageDetail < ActiveRecord::Migration[7.0]
  def change
    add_column :pdf_page_details, :error_message, :text, null: true, default: nil
  end
end

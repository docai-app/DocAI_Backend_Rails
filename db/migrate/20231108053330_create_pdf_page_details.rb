# frozen_string_literal: true

class CreatePdfPageDetails < ActiveRecord::Migration[7.0]
  def change
    create_table :pdf_page_details, id: :uuid do |t|
      t.references :document, null: false, foreign_key: true, type: :uuid
      t.integer :page_number
      t.text :summary
      t.string :keywords
      t.integer :status, null: false, default: 0
      t.integer :retry_count, default: 0, null: false

      t.timestamps
    end
  end
end

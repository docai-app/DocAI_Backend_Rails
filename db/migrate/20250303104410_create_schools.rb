# frozen_string_literal: true

class CreateSchools < ActiveRecord::Migration[7.0]
  def change
    create_table :schools, id: :uuid do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :code, null: false, index: { unique: true }
      t.integer :status, default: 0
      t.string :address
      t.string :contact_email
      t.string :contact_phone
      t.string :timezone
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end
  end
end

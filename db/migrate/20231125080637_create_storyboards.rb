# frozen_string_literal: true

class CreateStoryboards < ActiveRecord::Migration[7.0]
  def change
    create_table :storyboards, id: :uuid do |t|
      t.string :title, null: false
      t.text :description, null: true
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end

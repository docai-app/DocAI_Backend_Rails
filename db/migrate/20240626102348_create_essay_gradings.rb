# frozen_string_literal: true

class CreateEssayGradings < ActiveRecord::Migration[7.0]
  def change
    create_table :essay_gradings, id: :uuid do |t|
      t.text :essay
      t.string :topic
      t.integer :status, null: false, default: 0
      t.jsonb :grading, default: {}, null: false
      t.uuid :general_user_id, null: false

      t.timestamps
    end

    add_foreign_key :essay_gradings, :general_users, column: :general_user_id
  end
end

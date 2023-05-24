# frozen_string_literal: true

class CreateTagFunctions < ActiveRecord::Migration[7.0]
  def change
    create_table :tag_functions, id: :uuid do |t|
      t.uuid :tag_id, null: false, index: true, foreign_key: true
      t.uuid :function_id, null: false, index: true, foreign_key: true
      t.timestamps
    end
  end
end

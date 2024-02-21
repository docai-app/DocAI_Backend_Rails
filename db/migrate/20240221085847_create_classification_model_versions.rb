# frozen_string_literal: true

class CreateClassificationModelVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :classification_model_versions, id: :uuid do |t|
      t.string :model_name, null: false
      t.string :entity_name, null: false, index: true
      t.string :description, default: ''
      t.uuid :pervious_version_id, index: true, foreign_key: true, null: true
      t.jsonb :meta, default: {}

      t.timestamps
    end
  end
end

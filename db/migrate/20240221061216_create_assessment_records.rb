# frozen_string_literal: true

class CreateAssessmentRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :assessment_records, id: :uuid do |t|
      t.string :title
      t.jsonb :record
      t.jsonb :meta
      t.references :recordable, polymorphic: true, type: :uuid, index: true

      t.timestamps
    end
  end
end

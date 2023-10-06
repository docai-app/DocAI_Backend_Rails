# frozen_string_literal: true

class CreateDags < ActiveRecord::Migration[7.0]
  def change
    create_table :dags, id: :uuid do |t|
      t.references :user, null: true, foreign_key: true, type: :uuid, index: true
      t.string :dag_name
      t.integer :dag_status, default: 0
      t.jsonb :meta, default: {}
      t.jsonb :statistic, default: {}
      t.jsonb :dag_meta, default: {}

      t.timestamps
    end
  end
end

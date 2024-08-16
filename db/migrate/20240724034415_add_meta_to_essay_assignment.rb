# frozen_string_literal: true

class AddMetaToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :meta, :jsonb, default: {}, null: false
  end
end

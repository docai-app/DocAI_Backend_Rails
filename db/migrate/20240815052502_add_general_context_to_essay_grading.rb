# frozen_string_literal: true

class AddGeneralContextToEssayGrading < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_gradings, :general_context, :jsonb, null: false, default: {}
    add_column :essay_gradings, :using_time, :integer, null: false, default: 0
  end
end

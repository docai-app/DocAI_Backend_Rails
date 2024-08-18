class AddMetaToEssayGrading < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_gradings, :meta, :jsonb, null: false, default: {}
  end
end

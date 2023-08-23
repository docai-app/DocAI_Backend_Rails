class AddMetaOnTheTagTable < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :meta, :jsonb, default: {}, null: true
  end
end

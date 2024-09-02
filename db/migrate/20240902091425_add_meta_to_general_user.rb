class AddMetaToGeneralUser < ActiveRecord::Migration[7.0]
  def change
    add_column :general_users, :meta, :jsonb, default: {}, null: false
  end
end

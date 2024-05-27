class CreateDifyApiKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :dify_api_keys, id: :uuid do |t|
      t.string :domain, null: false
      t.string :workspace, null: false
      t.string :api_key, null: false
      t.datetime :actived_at

      t.timestamps
    end

    add_index :dify_api_keys, [:domain, :workspace], unique: true
  end
end
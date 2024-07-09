# frozen_string_literal: true

class AddUserIdAndSlugToLinkSet < ActiveRecord::Migration[7.0]
  def change
    add_column :link_sets, :user_id, :uuid
    add_column :link_sets, :slug, :string

    add_column :links, :slug, :string

    add_index :links, :slug, unique: true
    add_index :link_sets, :slug, unique: true
    add_index :link_sets, :user_id
    # 確保 pgcrypto 擴展被啟用，以便使用 gen_random_uuid() 函數
    enable_extension 'pgcrypto'
  end
end

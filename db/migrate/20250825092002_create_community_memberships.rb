# frozen_string_literal: true

class CreateCommunityMemberships < ActiveRecord::Migration[7.0]
  def change

    create_table :community_memberships, id: :uuid do |t|
      t.references :community, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.jsonb :meta, null: false, default: {}
      
      t.timestamps
    end

    add_index :community_memberships, [:community_id, :general_user_id], 
              unique: true, name: 'index_community_memberships_on_community_and_user'
  end
end
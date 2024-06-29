class AddGeneralUserIdToEssayAssignment < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_assignments, :general_user_id, :uuid
    add_index :essay_assignments, :general_user_id
  end
end

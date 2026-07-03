# frozen_string_literal: true

class CreateEssayAssignmentShares < ActiveRecord::Migration[7.0]
  def change
    create_table :essay_assignment_shares, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.uuid :owner_general_user_id, null: false
      t.uuid :shared_with_general_user_id, null: false
      t.uuid :shared_by_general_user_id, null: false
      t.references :school, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: true, foreign_key: true, type: :uuid
      t.integer :status, null: false, default: 0
      t.datetime :revoked_at
      t.datetime :notified_at

      t.timestamps
    end

    add_index :essay_assignment_shares,
              %i[essay_assignment_id shared_with_general_user_id],
              unique: true,
              name: 'idx_ea_shares_unique_recipient'

    add_index :essay_assignment_shares,
              %i[shared_with_general_user_id status],
              name: 'idx_ea_shares_recipient_status'

    add_index :essay_assignment_shares,
              %i[essay_assignment_id status],
              name: 'idx_ea_shares_assignment_status'

    add_foreign_key :essay_assignment_shares, :general_users, column: :owner_general_user_id
    add_foreign_key :essay_assignment_shares, :general_users, column: :shared_with_general_user_id
    add_foreign_key :essay_assignment_shares, :general_users, column: :shared_by_general_user_id
  end
end

# frozen_string_literal: true

class AddIndexOnEssayAssignmentsUserUpdatedAt < ActiveRecord::Migration[7.0]
  def change
    add_index :essay_assignments,
              %i[general_user_id updated_at],
              order: { updated_at: :desc },
              name: 'index_essay_assignments_on_user_updated_at',
              if_not_exists: true
  end
end

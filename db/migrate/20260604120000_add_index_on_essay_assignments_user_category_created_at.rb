# frozen_string_literal: true

class AddIndexOnEssayAssignmentsUserCategoryCreatedAt < ActiveRecord::Migration[7.0]
  def change
    add_index :essay_assignments,
              %i[general_user_id category created_at],
              order: { created_at: :desc },
              name: 'index_essay_assignments_on_user_category_created_at'
  end
end

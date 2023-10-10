# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflow_steps
#
#  id                  :uuid             not null, primary key
#  position            :integer
#  name                :string           not null
#  description         :string
#  user_id             :uuid
#  project_workflow_id :uuid
#  status              :integer          default("pending")
#  is_human            :boolean          default(TRUE)
#  meta                :jsonb
#  dag_meta            :jsonb
#  deadline            :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assignee_id         :uuid
#
class ProjectWorkflowStep < ApplicationRecord
  belongs_to :user, class_name: 'User', foreign_key: 'user_id', optional: true
  belongs_to :assignee, class_name: 'User', foreign_key: 'assignee_id', optional: true
  belongs_to :project_workflow

  before_save :store_assignee_id
  after_save :handle_assignee_change

  enum status: {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3
  }

  def store_assignee_id
    @old_assignee_id = assignee_id_was if assignee_id_changed?
  end

  # Attributes related macros
  def handle_assignee_change
    return unless saved_change_to_assignee_id?

    chatbot = Chatbot.find_by(object_id: project_workflow_id, object_type: 'ProjectWorkflow')
    if chatbot.add_message('system', 'talk', "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}",
                           { belongs_user_id: assignee_id })
      puts "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}"
      ActionCable.server.broadcast(
        "chat_ProjectWorkflow_#{chatbot.id}_#{assignee_id}", { message: "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}" }
      )
    end
  end
end

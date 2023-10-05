# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflows
#
#  id                  :uuid             not null, primary key
#  name                :string           not null
#  status              :integer          default("draft"), not null
#  description         :string
#  user_id             :uuid
#  is_process_workflow :boolean          default(FALSE)
#  deadline            :datetime
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  folder_id           :uuid
#
class ProjectWorkflow < ApplicationRecord
  has_one :chatbot, dependent: :destroy, class_name: 'Chatbot', foreign_key: 'object_id'
  has_many :steps, lambda {
                     order(position: :asc)
                   }, dependent: :destroy, class_name: 'ProjectWorkflowStep', foreign_key: 'project_workflow_id'
  belongs_to :folder, optional: true, class_name: 'Folder'
  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'

  enum status: {
    draft: 0,
    running: 1,
    finish: 2
  }
end

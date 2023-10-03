# frozen_string_literal: true

class ProjectWorkflowStep < ApplicationRecord
  belongs_to :user
  belongs_to :project_workflow
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: project_tasks
#
#  id           :uuid             not null, primary key
#  title        :string           default("New Project Task"), not null
#  description  :text
#  project_id   :uuid             not null
#  user_id      :uuid             not null
#  is_completed :boolean          default(FALSE), not null
#  order        :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  deadline_at  :datetime
#
class ProjectTask < ApplicationRecord
  resourcify

  belongs_to :project, class_name: 'Project', foreign_key: 'project_id'
  belongs_to :user, class_name: 'User', foreign_key: 'user_id'
end

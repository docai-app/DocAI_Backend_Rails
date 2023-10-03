# frozen_string_literal: true

# == Schema Information
#
# Table name: projects
#
#  id          :uuid             not null, primary key
#  name        :string           default("New Project"), not null
#  description :string
#  user_id     :uuid             not null
#  folder_id   :uuid             not null
#  is_public   :boolean          default(FALSE)
#  is_finished :boolean          default(FALSE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  deadline_at :datetime
#
class Project < ApplicationRecord
  resourcify

  belongs_to :user, class_name: 'User', foreign_key: 'user_id'
  belongs_to :folder, class_name: 'Folder', foreign_key: 'folder_id'

  has_many :documents, through: :folder, class_name: 'Document', dependent: :destroy
  has_many :project_tasks, class_name: 'ProjectTask', foreign_key: 'project_id', dependent: :destroy

  after_create :set_permissions_to_owner

  paginates_per 20

  def set_permissions_to_owner
    return if self['user_id'].nil?

    user.add_role :r, self
    user.add_role :w, self
  end
end

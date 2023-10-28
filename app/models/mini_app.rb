# frozen_string_literal: true

# == Schema Information
#
# Table name: mini_apps
#
#  id          :uuid             not null, primary key
#  name        :string
#  description :string
#  meta        :jsonb
#  user_id     :uuid             not null
#  folder_id   :uuid
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class MiniApp < ApplicationRecord
  resourcify

  acts_as_taggable_on :document_labels, :app_functions

  belongs_to :user, class_name: 'User', foreign_key: 'user_id'
  belongs_to :folder, dependent: :destroy, class_name: 'Folder', foreign_key: 'folder_id'
end

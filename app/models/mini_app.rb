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
# Indexes
#
#  index_mini_apps_on_folder_id  (folder_id)
#  index_mini_apps_on_folder_id  (folder_id)
#  index_mini_apps_on_user_id    (user_id)
#  index_mini_apps_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (folder_id => folders.id)
#  fk_rails_...  (folder_id => public.folders.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (user_id => public.users.id)
#
class MiniApp < ApplicationRecord
  resourcify

  acts_as_taggable_on :document_labels, :app_functions

  belongs_to :user, class_name: 'User', foreign_key: 'user_id'
  belongs_to :folder, dependent: :destroy, class_name: 'Folder', foreign_key: 'folder_id'
end

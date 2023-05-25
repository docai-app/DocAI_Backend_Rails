# frozen_string_literal: true

class MiniApp < ApplicationRecord
  resourcify

  acts_as_taggable_on :document_labels, :app_functions

  belongs_to :user, class_name: 'User', foreign_key: 'user_id'
  belongs_to :folder, dependent: :destroy, class_name: 'Folder', foreign_key: 'folder_id'
end

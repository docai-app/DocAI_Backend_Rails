class Project < ApplicationRecord
    resourcify

    belongs_to :user, class_name: 'User', foreign_key: 'user_id'

    has_one :folder, class_name: 'Folder', foreign_key: 'folder_id'
    has_many :documents, through: :folder, class_name: 'Document', foreign_key: 'folder_id'
end

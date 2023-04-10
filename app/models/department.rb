class Department < ApplicationRecord
  has_many :users
  has_many :documents, class_name: 'Document', foreign_key: "department_id"

  validates :name, presence: true, uniqueness: true
end

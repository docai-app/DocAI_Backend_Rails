# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :uuid             not null, primary key
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  nickname               :string
#  phone                  :string
#  position               :string
#  date_of_birth          :date
#  sex                    :integer
#  profile                :jsonb
#
class User < ApplicationRecord
  rolify
  # include Devise::JWT::RevocationStrategies::JTIMatcher
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  # devise :database_authenticatable, :registerable,
  #        :recoverable, :rememberable, :validatable
  devise :database_authenticatable,
         :jwt_authenticatable,
         :registerable,
         jwt_revocation_strategy: JwtDenylist

  # belongs_to :department, class_name: 'Department', foreign_key: "department_id", optional: true

  has_and_belongs_to_many :roles, join_table: :users_roles
  has_many :approval_documents, class_name: 'Document', foreign_key: 'approval_user_id'
  has_many :documents, class_name: 'Document', foreign_key: 'user_id'
  has_many :folders, class_name: 'Folder', foreign_key: 'user_id'
  has_many :projects, class_name: 'Project', foreign_key: 'user_id'
  has_many :project_tasks, class_name: 'ProjectTask', foreign_key: 'user_id'
  has_many :mini_apps, class_name: 'MiniApp', foreign_key: 'user_id'
  has_many :chatbots, class_name: 'Chatbot', foreign_key: 'user_id'
  has_many :smart_extraction_schemas, class_name: 'SmartExtractionSchema', foreign_key: 'user_id'
  has_many :project_workflows, class_name: 'ProjectWorkflow', foreign_key: 'user_id'

  validates_confirmation_of :password
  # after_create :assign_default_role
  # def assign_default_role
  #   add_role(:user) if roles.blank?
  # end

  def jwt_payload
    {
      'sub' => id,
      'iat' => Time.now.to_i,
      'email' => email
    }
  end
end

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
         :omniauthable,
         jwt_revocation_strategy: JwtDenylist,
         omniauth_providers: [:google_oauth2]

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
  has_one :system_assistant, lambda {
    where(object_type: 'UserSystemAssistant')
  }, class_name: 'Chatbot', foreign_key: 'user_id', dependent: :destroy
  has_many :identities, dependent: :destroy

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

  def find_for_google_oauth2(access_token, _signed_in_resource = nil)
    access_token.info
    user = Identity.where(provider: 'Google', uid: access_token.uid).first&.user
    # user = User.where(:google_token => access_token.credentials.token, :google_uid => access_token.uid ).first
    return user if user

    existing_user = current_user
    return unless existing_user

    existing_user.identities.find_or_create_by(provider: 'Google', uid: access_token.uid,
                                               meta: { google_token: access_token.credentials.token })
    # existing_user.google_uid = access_token.uid
    # existing_user.google_token = access_token.credentials.token
    # existing_user.save!
    existing_user
  end

  def read_gmail_list
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_ID'],
      client_secret: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_SECRET'],
      refresh_token: google_token,
      scope: 'https://www.googleapis.com/auth/gmail.readonly'
    )

    gmail = Google::Apis::GmailV1::GmailService.new
    gmail.authorization = credentials

    result = gmail.list_user_messages('me', max_results: 10)

    if result.messages.any?
      result.messages.each do |message|
        full_message = gmail.get_user_message('me', message.id)

        message_content = full_message.payload.body.data || 'No Content'
        message_content_utf8 = message_content.scrub('').force_encoding('UTF-8')
        puts "Message Content: #{message_content_utf8}"
        puts '------------------------'
      end
    else
      puts 'No messages found.'
    end
  end
end

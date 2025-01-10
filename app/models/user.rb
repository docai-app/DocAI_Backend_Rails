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
#  failed_attempts        :integer          default(0), not null
#  unlock_token           :string
#  locked_at              :datetime
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
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
         :lockable,
         :omniauthable, omniauth_providers: [:google_oauth2],
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
  has_one :system_assistant, lambda {
    where(object_type: 'UserSystemAssistant')
  }, class_name: 'Chatbot', foreign_key: 'user_id', dependent: :destroy
  has_many :identities, dependent: :destroy, class_name: 'Identity', foreign_key: 'user_id'
  has_one :active_api_key, lambda {
                             where(active: true).where(tenant: Apartment::Tenant.current)
                           }, class_name: 'ApiKey', foreign_key: 'user_id', dependent: :destroy
  has_many :storyboards, class_name: 'Storyboard', foreign_key: 'user_id', dependent: :destroy
  has_many :storyboard_items, lambda {
                                where(is_ready: true).where(status: :saved)
                              }, class_name: 'StoryboardItem', foreign_key: 'user_id', dependent: :destroy
  has_one :energy, as: :user, dependent: :destroy
  has_many :purchases, as: :user, dependent: :destroy
  has_many :purchased_marketplace_items, through: :purchases, source: :marketplace_item

  has_many :assessment_records, as: :recordable

  after_create :create_user_api_key

  validates_confirmation_of :password
  # after_create :assign_default_role
  # def assign_default_role
  #   add_role(:user) if roles.blank?
  # end

  require 'google/apis/gmail_v1'

  store_accessor :konnecai_tokens, :essay, :report, :other_type

  def jwt_payload
    {
      'sub' => id,
      'iat' => Time.now.to_i,
      'email' => email
    }
  end

  def self.find_for_google_oauth2(uid, access_token, refresh_token, current_user = nil)
    user = Identity.where(provider: 'Google', user_id: current_user.id).first&.user

    if user
      user.identities.find_by(provider: 'Google').update!(
        meta: { google_token: access_token, google_refresh_token: refresh_token }, uid:
      )
      return user
    end

    existing_user = current_user
    return unless existing_user

    existing_user.identities.find_or_create_by(provider: 'Google', uid:,
                                               meta: { google_token: access_token, google_refresh_token: refresh_token })
    existing_user
  end

  def read_gmail_list
    puts 'read_gmail_list'
    puts "refresh_token: #{identities.find_by(provider: 'Google').meta['google_refresh_token']}"

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_ID'],
      client_secret: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_SECRET'],
      refresh_token: identities.find_by(provider: 'Google').meta['google_refresh_token'],
      scope: 'https://www.googleapis.com/auth/gmail.readonly'
    )

    gmail = Google::Apis::GmailV1::GmailService.new
    gmail.authorization = credentials

    # Doesn't have attachments
    no_attachments_result = gmail.list_user_messages('me', max_results: 10, include_spam_trash: false,
                                                           q: 'after:2023/10/30 !has:attachment')
    puts "No Attachments Result: #{no_attachments_result.inspect}"

    if no_attachments_result.messages
      no_attachments_result.messages.each do |message|
        # puts "Message: #{message.inspect}"

        full_message = gmail.get_user_message('me', message.id)
        internal_date = full_message.internal_date.to_s.chop.chop.chop
        puts "Full Message Internal Date: #{internal_date}"
        created_at = Time.at(internal_date.to_i)
        puts "Full Message Created At: #{created_at}"
        # Find the full_message payload header array one item named 'Subject'
        puts "Full Message Payload Headers: #{full_message.payload.headers.pretty_inspect}"
        subject = full_message.payload.headers.find { |header| header.name == 'Subject' }
        puts "Full Message Subject: #{subject.value}"
        message_date = full_message.payload.headers.find { |header| header.name == 'Date' }
        puts "Full Message Date: #{message_date.value}"
        message_from = full_message.payload.headers.find { |header| header.name == 'From' }
        puts "Full Message From: #{message_from.value}"
        message_to = full_message.payload.headers.find { |header| header.name == 'To' }
        puts "Full Message To: #{message_to.value}"

        message_content_utf8 = full_message.payload.parts.second.body.data.scrub('').force_encoding('UTF-8')
        puts "Message Content UTF-8: #{message_content_utf8}"
        puts '------------------------\n\n'
      rescue StandardError => e
        puts "Exception: #{e}"
        puts '------------------------\n\n'
        next

        # puts "Full Message Payload Second Parts Second Parts Body Data: #{full_message.payload.parts.second.body.data.to_s}"
        # puts "Full Message Payload Second Parts Body Data: #{full_message.payload.parts.second.pretty_inspect}"
        # puts "Full Message Payload Second Parts Body Data to_s: #{full_message.payload.parts.second.body.data.to_s}"
        # puts "Full message payload body data: #{full_message.payload.body.inspect}"
        # message_content = full_message.payload.body.data || 'No Content'
        # puts "Message Content: #{message_content}"
      end
    else
      puts 'No messages found.'
    end

    # Has attachments
    # attachments_result = gmail.list_user_messages('me', max_results: 20, include_spam_trash: false, q: 'after:2023/10/30 has:attachment', )

    # if attachments_result.messages
    #   attachments_result.messages.each do |message|
    #     # Write the try catch block here:
    #     begin
    #       full_message = gmail.get_user_message('me', message.id)
    #       internal_date = full_message.internal_date.to_s.chop.chop.chop
    #       puts "Full Message Internal Date: #{internal_date}"
    #       created_at = Time.at(internal_date.to_i)
    #       puts "Full Message Created At: #{created_at}"
    #       # Find the full_message payload header array one item named 'Subject'
    #       subject = full_message.payload.headers.find { |header| header.name == 'Subject' }
    #       puts "Full Message Subject: #{subject.value}"

    #       puts "Full Message Payload Second Parts Second Parts Body Data: #{full_message.payload.parts.first.parts.last.body.data.to_s}"
    #       message_content_utf8 = full_message.payload.parts.first.parts.last.body.data.scrub('').force_encoding('UTF-8')
    #       puts "Message Content UTF-8: #{message_content_utf8}"
    #       puts '------------------------\n\n'
    #     rescue => exception
    #       puts "Exception: #{exception}"
    #       puts '------------------------\n\n'
    #       next
    #     end
    #     # puts "Full Message Payload Second Parts Second Parts Body Data: #{full_message.payload.parts.second.body.data.to_s}"
    #     # puts "Full Message Payload Second Parts Body Data: #{full_message.payload.parts.second.pretty_inspect}"
    #     # puts "Full Message Payload Second Parts Body Data to_s: #{full_message.payload.parts.second.body.data.to_s}"
    #     # puts "Full message payload body data: #{full_message.payload.body.inspect}"
    #     # message_content = full_message.payload.body.data || 'No Content'
    #     # puts "Message Content: #{message_content}"
    #   end
    # else
    #   puts 'No messages found.'
    # end
  end

  def send_gmail(to, subject, content)
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_ID'],
      client_secret: ENV['GOOGLE_GMAIL_READ_INCOMING_CLIENT_SECRET'],
      refresh_token: identities.find_by(provider: 'Google').meta['google_refresh_token'],
      scope: 'https://www.googleapis.com/auth/gmail.send'
    )

    gmail = Google::Apis::GmailV1::GmailService.new
    gmail.authorization = credentials

    message = Google::Apis::GmailV1::Message.new(raw: create_email(to, subject, content).to_s)

    gmail.send_user_message('me', message)
  end

  def create_user_api_key
    tenant = Apartment::Tenant.current
    ApiKey.create!(
      tenant:,
      user_id: id
    )
  end

  private

  def create_email(to, subject, content)
    message = Mail.new
    message.date = Time.now
    message.subject = subject
    message.body = content
    message.to = to
    message.to_s
  end
end

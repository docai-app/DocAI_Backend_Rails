# frozen_string_literal: true

# == Schema Information
#
# Table name: documents
#
#  id                :uuid             not null, primary key
#  name              :string
#  storage_url       :string
#  content           :text
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  approval_status   :integer          default("awaiting"), not null
#  approval_user_id  :uuid
#  approval_at       :datetime
#  folder_id         :uuid
#  upload_local_path :string
#
class Document < ApplicationRecord
  resourcify
  acts_as_taggable_on :labels
  # The status of the document.
  # pending is the default status.
  # uploaded is when the file is uploaded to the cloud.
  # confirmed is when the file is confirmed by the user after ready to be ocr-ed.
  # ocring is when the file is being ocr-ed.
  # ocr_completed is when the file is ocr-ed.
  # ready is when the file is ready to be used. This status is pre-confirm status. When the user confirms the file, the status will be changed to confirmed.
  enum status: %i[pending uploaded confirmed ocring ocr_completed ready]
  enum approval_status: %i[awaiting rejected approved]
  has_one_attached :file # , service: :microsoft
  has_paper_trail

  has_many :document_approval, dependent: :destroy, class_name: 'DocumentApproval', foreign_key: 'document_id'

  belongs_to :approval_user, optional: true, class_name: 'User', foreign_key: 'approval_user_id'
  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'
  belongs_to :folder, optional: true, class_name: 'Folder', foreign_key: 'folder_id'
  has_many :form_data, dependent: :destroy, class_name: 'FormDatum', foreign_key: 'document_id'
  # belongs_to :department

  scope :waiting_approve, lambda { |_b|
    where('documents.approval_at is null')
  }

  scope :approved, -> { where('documents.approval_at is not null') }

  def self.last
    order('documents.created_at desc').limit(1).first
  end

  def has_file_uploaded?
    self['storage_url'].present? || file.url.present?
  end

  def update_upload_status
    return unless self['status'] == 'pending' && has_file_uploaded?

    self.status = 'uploaded'
    save
  end

  def has_rights_to_read?(user)
    return true unless !user_id.nil? && self.user != user

    user.has_role? :r, self
  end

  def has_rights_to_write?(user)
    return true unless !user_id.nil? && self.user != user

    puts 'Checking role'
    user.has_role? :w, self
  end
end

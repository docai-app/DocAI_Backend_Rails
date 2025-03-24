# frozen_string_literal: true

# == Schema Information
#
# Table name: documents
#
#  id                    :uuid             not null, primary key
#  name                  :string
#  storage_url           :string
#  content               :text
#  status                :integer          default("pending"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  approval_status       :integer          default("awaiting"), not null
#  approval_user_id      :uuid
#  approval_at           :datetime
#  folder_id             :uuid
#  upload_local_path     :string
#  user_id               :uuid
#  is_classified         :boolean          default(FALSE)
#  is_document           :boolean          default(TRUE)
#  meta                  :jsonb
#  is_classifier_trained :boolean          default(FALSE)
#  is_embedded           :boolean          default(FALSE)
#  error_message         :text
#  retry_count           :integer          default(0)
#
# Indexes
#
#  index_documents_on_approval_status    (approval_status)
#  index_documents_on_approval_user_id   (approval_user_id)
#  index_documents_on_folder_id          (folder_id)
#  index_documents_on_name               (name)
#  index_documents_on_status             (status)
#  index_documents_on_upload_local_path  (upload_local_path)
#  index_documents_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (folder_id => folders.id)
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
  has_many :document_smart_extraction_data, dependent: :destroy, class_name: 'DocumentSmartExtractionDatum',
                                            foreign_key: 'document_id'
  has_many :smart_extraction_schema, through: :document_smart_extraction_data, class_name: 'SmartExtractionSchema',
                                     foreign_key: 'smart_extraction_schema_id'
  has_many :pdf_page_details, dependent: :destroy, class_name: 'PdfPageDetail', foreign_key: 'document_id'

  after_create :process_pdf_if_applicable

  scope :waiting_approve, lambda { |_b|
    where('documents.approval_at is null')
  }

  scope :approved, -> { where('documents.approval_at is not null') }

  def self.with_ancestor_folder_ids(conditions)
    where_clause = conditions.to_sql

    sql = <<-SQL
      WITH RECURSIVE folder_ancestors AS (
          SELECT f.id, f.parent_id, d.id as document_id
          FROM folders f
          JOIN documents d ON f.id = d.folder_id
          WHERE #{where_clause}

          UNION ALL

          SELECT f.id, f.parent_id, fa.document_id
          FROM folders f
          JOIN folder_ancestors fa ON f.id = fa.parent_id
      ),
      all_ancestors AS (
          SELECT
              document_id,
              string_agg(folder_ancestors.id::text, ',') AS parent_folder_ids
          FROM folder_ancestors
          GROUP BY document_id
      )
      SELECT d.*, a.parent_folder_ids
      FROM documents d
      LEFT JOIN all_ancestors a ON d.id = a.document_id;
    SQL

    find_by_sql(sql)

    # 使用方法
    # conditions = Document.where('created_at > ?', 1.week.ago)
    # @documents = Document.with_ancestor_folder_ids(conditions)
  end

  def self.accessible_by_user(user_id, conditions)
    where_clause = conditions.to_sql
    sql = <<-SQL
      WITH RECURSIVE folder_ancestors AS (
          SELECT f.id, f.parent_id, d.id as document_id
          FROM folders f
          JOIN documents d ON f.id = d.folder_id
          WHERE (d.id in (#{where_clause})) or (d.folder_id is null)

          UNION ALL

          SELECT f.id, f.parent_id, fa.document_id
          FROM folders f
          JOIN folder_ancestors fa ON f.id = fa.parent_id
      ),
      all_ancestors AS (
          SELECT
              document_id,
              string_agg(folder_ancestors.id::text, ',') AS parent_folder_ids
          FROM folder_ancestors
          GROUP BY document_id
      ),
      user_accessible_documents AS (
        SELECT d.*
        FROM documents d
        LEFT JOIN all_ancestors a ON d.id = a.document_id
        LEFT JOIN LATERAL unnest(string_to_array(COALESCE(a.parent_folder_ids, ''), ',')) AS ancestor_folder(id) ON true
        LEFT JOIN roles r ON r.resource_type = 'Folder' AND r.resource_id = ancestor_folder.id::uuid
        LEFT JOIN users_roles ur ON ur.role_id = r.id
        WHERE (ur.user_id = '#{user_id}' AND d.id in (#{where_clause})) OR (d.user_id = '#{user_id}' AND d.id in (#{where_clause}))
        GROUP BY d.id
      )
      SELECT id
      FROM user_accessible_documents;
    SQL

    find_by_sql(sql)
  end

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

  def max_retry
    3
  end

  def is_max_retry?
    retry_count >= max_retry
  end

  def process_pdf_if_applicable
    puts 'Process PDF If Applicable!'
    return unless DocumentService.checkFileUrlIsPDF(storage_url)

    PdfPageDetailService.process(self, Apartment::Tenant.current)
  end
end

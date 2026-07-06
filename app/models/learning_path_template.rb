# frozen_string_literal: true

class LearningPathTemplate < ApplicationRecord
  enum status: { draft: 0, active: 1, archived: 2 }

  belongs_to :created_by, class_name: 'GeneralUser', optional: true
  has_many :assignment_packages, dependent: :nullify

  validates :title, presence: true
  validates :category, presence: true
  validate :json_fields_are_hashes

  scope :visible_to_students, -> { active.order(position: :asc, created_at: :desc) }

  def as_student_json
    {
      id: id,
      title: title,
      description: description,
      emoji: emoji,
      level: level,
      locale: locale,
      category: category,
      prompt_config: prompt_config,
      position: position,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def as_admin_json
    as_student_json.merge(
      status: status,
      dify_config: dify_config,
      usage_policy: usage_policy,
      created_by_id: created_by_id
    )
  end

  private

  def json_fields_are_hashes
    %i[prompt_config dify_config usage_policy].each do |field|
      errors.add(field, 'must be a JSON object') unless public_send(field).is_a?(Hash)
    end
  end
end

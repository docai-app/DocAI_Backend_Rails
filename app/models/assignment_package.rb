# frozen_string_literal: true

class AssignmentPackage < ApplicationRecord
  enum status: { generating: 0, active: 1, completed: 2, failed: 3, archived: 4 }

  belongs_to :general_user
  belongs_to :learning_path_template, optional: true
  has_many :assignment_package_items, -> { order(position: :asc) }, dependent: :destroy
  has_many :essay_assignments, through: :assignment_package_items

  before_destroy :destroy_generated_assignments

  validates :title, presence: true
  validate :json_fields_are_hashes

  def owned_by?(user)
    user.present? && general_user_id == user.id
  end

  def deletable_by_student?(user)
    owned_by?(user) && failed?
  end

  def refresh_progress!
    total = assignment_package_items.count
    completed_count = assignment_package_items.completed.count
    current_item = assignment_package_items.where(status: :available).first

    update!(
      progress: {
        'total_items' => total,
        'completed_items' => completed_count,
        'current_position' => current_item&.position,
        'completion_percentage' => total.zero? ? 0 : ((completed_count.to_f / total) * 100).round
      },
      status: total.positive? && completed_count == total ? :completed : status
    )
  end

  def as_list_json
    payload = {
      id: id,
      title: title,
      description: description,
      status: status,
      summary: summary,
      progress: progress,
      learning_path_template_id: learning_path_template_id,
      learner_profile_id: learner_profile_id,
      current_item: current_item&.as_json_for_package,
      created_at: created_at,
      updated_at: updated_at
    }

    if completed?
      payload[:score_summary] = AssignmentPackages::PackageScoreSummary.for(self)
      payload[:completed_at] = payload[:score_summary][:completed_at]
    end

    payload
  end

  def as_completed_detail_json
    as_list_json.merge(
      items: assignment_package_items.includes(:essay_assignment, :essay_grading).map(&:as_json_for_package)
    )
  end

  def as_detail_json
    as_list_json.merge(
      source_conversation: source_conversation,
      error: error,
      items: assignment_package_items.includes(:essay_assignment, :essay_grading).map(&:as_json_for_package)
    )
  end

  private

  def current_item
    assignment_package_items.available.order(:position).first ||
      assignment_package_items.locked.order(:position).first
  end

  def destroy_generated_assignments
    essay_assignments.find_each(&:destroy)
  end

  def json_fields_are_hashes
    %i[summary progress source_conversation dify_request dify_response error].each do |field|
      errors.add(field, 'must be a JSON object') unless public_send(field).is_a?(Hash)
    end
  end
end

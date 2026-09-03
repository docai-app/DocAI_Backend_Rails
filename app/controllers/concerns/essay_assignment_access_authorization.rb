# frozen_string_literal: true

module EssayAssignmentAccessAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_essay_assignment_owner!
    return if performed?
    return if current_general_user&.aienglish_global_admin?
    return if @essay_assignment&.owned_by?(current_general_user)

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_access!
    return if performed?
    return if current_general_user&.aienglish_global_admin?
    return if @essay_assignment&.accessible_by?(current_general_user)

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_manage!
    return if performed?
    return if current_general_user&.aienglish_global_admin?
    return if assignment_manageable_by_current_user?

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_read!
    return if performed?
    return if current_general_user&.aienglish_global_admin?
    return if assignment_manageable_by_current_user?

    assignment = @essay_assignment
    student = current_general_user
    if assignment.present? && student&.aienglish_role == 'student'
      # The web grading and draft editors use /read, including code-joined work
      # without a distribution and historical work after feature/year changes.
      return if assignment.assigned_to_student?(student)
      return if assignment.essay_gradings.exists?(general_user_id: student.id)
    end

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_score_release!
    return if performed?
    return if current_general_user&.aienglish_global_admin?
    return if @essay_assignment&.can_release_scores?(current_general_user)

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def assignment_manageable_by_current_user?
    assignment = @essay_assignment
    user = current_general_user
    return false if assignment.blank? || user.blank?
    return true if user.aienglish_global_admin?

    return true if assignment.owned_by?(user)
    return false unless assignment.shared_with?(user)

    assignment.category_enabled_for?(user)
  end
end

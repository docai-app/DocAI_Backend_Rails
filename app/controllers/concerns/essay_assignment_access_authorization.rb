# frozen_string_literal: true

module EssayAssignmentAccessAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_essay_assignment_owner!
    return if performed?
    return if @essay_assignment&.owned_by?(current_general_user)

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_access!
    return if performed?
    return if assignment_manageable_by_current_user?

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def authorize_essay_assignment_manage!
    return if performed?
    return if assignment_manageable_by_current_user?

    render json: { success: false, error: 'Forbidden' }, status: :forbidden
  end

  def assignment_manageable_by_current_user?
    assignment = @essay_assignment
    user = current_general_user
    return false if assignment.blank? || user.blank?

    return true if assignment.owned_by?(user)
    return false unless assignment.shared_with?(user)

    assignment.category_enabled_for?(user)
  end
end

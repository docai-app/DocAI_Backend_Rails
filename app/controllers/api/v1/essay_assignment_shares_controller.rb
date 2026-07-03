# frozen_string_literal: true

module Api
  module V1
    class EssayAssignmentSharesController < ApiController
      include EssayAssignmentAccessAuthorization

      before_action :authenticate_general_user!
      before_action :ensure_teacher!
      before_action :set_essay_assignment, only: %i[index sync share]
      # before_action :authorize_essay_assignment_owner!, only: %i[index sync share]

      def share_options
        school = EssayAssignmentShareService.school_for_teacher(current_general_user)
        return render_school_required unless school

        payload = EssayAssignmentShareService.school_teacher_candidates(
          school: school,
          exclude_user: current_general_user
        )

        render json: {
          success: true,
          teachers: payload[:teachers],
          options: {
            school: { id: school.id, name: school.name },
            departments: payload[:departments],
            teachers: payload[:teachers]
          }
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def index
        render json: {
          success: true,
          shared_teachers: active_shared_teacher_payloads
        }, status: :ok
      end

      def sync
        result = EssayAssignmentShareService.sync_shares!(
          assignment: @essay_assignment,
          actor: current_general_user,
          teacher_ids: share_teacher_ids_param
        )

        render json: {
          success: true,
          shared_teachers: result.shared_teachers
        }, status: :ok
      rescue EssayAssignmentShareService::ShareError => e
        status = e.details.present? ? :unprocessable_entity : :forbidden
        render json: {
          success: false,
          error: e.message,
          details: e.details
        }, status: status
      end
      alias share sync

      private

      def ensure_teacher!
        return if performed?
        return if current_general_user.aienglish_role == 'teacher'

        render json: { success: false, error: 'Only teachers can manage assignment shares' }, status: :forbidden
      end

      def set_essay_assignment
        return if performed?

        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def render_school_required
        render json: { success: false, error: 'School context is required' }, status: :unprocessable_entity
      end

      def share_teacher_ids_param
        if params[:teacher_ids].present?
          return Array(params[:teacher_ids]).map(&:to_s).reject(&:blank?)
        end

        emails = Array(params[:teacher_emails]).map(&:to_s).map(&:strip).reject(&:blank?)
        return [] if emails.empty?

        GeneralUser.where('LOWER(email) IN (?)', emails.map(&:downcase)).pluck(:id).map(&:to_s)
      end

      def active_shared_teacher_payloads
        @essay_assignment.active_essay_assignment_shares
                         .includes(:shared_with_general_user)
                         .map(&:teacher_json)
      end
    end
  end
end

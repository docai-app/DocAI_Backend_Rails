# frozen_string_literal: true

module Api
  module V1
    class EssayAssignmentSharesController < ApiController
      include EssayAssignmentAccessAuthorization

      before_action :authenticate_general_user!
      before_action :ensure_teacher!
      before_action :set_essay_assignment, only: %i[index sync share]
      before_action :authorize_essay_assignment_owner!, only: %i[index sync share]

      def share_options
        school = share_options_school
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
        return if current_general_user.aienglish_global_admin?
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

      def share_options_school
        if current_general_user.aienglish_global_admin? && params[:essay_assignment_id].present?
          assignment = EssayAssignment.includes(school_academic_year: :school)
                                      .find_by(id: params[:essay_assignment_id])
          return nil unless assignment

          school = assignment.school_academic_year&.school
          school ||= assignment.assignment_distributions
                              .where.not(school_id: nil)
                              .order(created_at: :desc)
                              .first
                              &.school
          return school
        end

        EssayAssignmentShareService.school_for_teacher(current_general_user)
      end

      def share_teacher_ids_param
        # Rails normalizes [null] into []; inspect JSON before that normalization
        # so a malformed payload cannot be mistaken for "remove all shares".
        source = request.media_type == 'application/json' ? JSON.parse(request.raw_post.presence || '{}') : params
        unless source.is_a?(Hash) || source.is_a?(ActionController::Parameters)
          raise_invalid_recipients!('invalid_share_payload')
        end
        if source.key?('teacher_ids')
          ids = source['teacher_ids']
          return ids if ids.is_a?(Array) && ids.all? { |id| id.is_a?(String) && id.present? }

          raise_invalid_recipients!('invalid_teacher_ids')
        end

        raw_emails = source['teacher_emails']
        unless source.key?('teacher_emails') && raw_emails.is_a?(Array) &&
               raw_emails.all? { |email| email.is_a?(String) && email.present? }
          raise_invalid_recipients!('invalid_teacher_emails')
        end

        emails = raw_emails.map { |email| email.strip.downcase }.uniq
        found = GeneralUser.where('LOWER(email) IN (?)', emails).pluck(:email, :id)
        ids_by_email = found.to_h { |email, id| [email.downcase, id.to_s] }
        # Unknown emails must not silently become an empty list that revokes shares.
        raise_invalid_recipients!('teacher_not_found') unless emails.all? { |email| ids_by_email.key?(email) }

        emails.map { |email| ids_by_email.fetch(email) }
      rescue JSON::ParserError
        raise_invalid_recipients!('invalid_share_payload')
      end

      def raise_invalid_recipients!(reason)
        raise EssayAssignmentShareService::ShareError.new('Invalid share recipients', details: [{ error: reason }])
      end

      def active_shared_teacher_payloads
        @essay_assignment.active_essay_assignment_shares
                         .includes(:shared_with_general_user)
                         .map(&:teacher_json)
      end
    end
  end
end

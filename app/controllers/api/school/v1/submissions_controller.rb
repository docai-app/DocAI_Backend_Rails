# frozen_string_literal: true

module Api
  module School
    module V1
      class SubmissionsController < SchoolApiController
        include SchoolPortalEssayGradingJson

        def show
          grading = EssayGrading.includes(:essay_assignment, :general_user).find_by(id: params[:id])
          unless grading && assignments_scope.exists?(id: grading.essay_assignment_id)
            return render json: { success: false, error: 'Submission not found' }, status: :not_found
          end

          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: 'submission_viewed',
            target: grading,
            request: request
          )

          render json: {
            success: true,
            data: {
              essay_grading: essay_grading_show_payload(grading)
            }
          }, status: :ok
        end
      end
    end
  end
end

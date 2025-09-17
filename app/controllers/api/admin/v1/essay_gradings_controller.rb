# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EssayGradingsController < AdminApiController
        # include AdminAuthenticator

        before_action :set_essay_grading, only: [:rerun_workflow]
        before_action :check_stopped_status, only: [:rerun_workflow]

        # POST /api/admin/v1/essay_gradings/:id/rerun_workflow
        def rerun_workflow
          begin
            @essay_grading.rerun_workflow
            render json: { 
              success: true, 
              message: 'Workflow rerun successfully',
              essay_grading: @essay_grading
            }, status: :ok
          rescue StandardError => e
            render json: { 
              success: false, 
              message: "Failed to rerun workflow: #{e.message}"
            }, status: :internal_server_error
          end
        end

        private

        def set_essay_grading
          @essay_grading = EssayGrading.find(params[:id])
        end

        def check_stopped_status
          unless @essay_grading.stopped?
            render json: { 
              success: false, 
              message: 'Essay grading is not in stopped status'
            }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
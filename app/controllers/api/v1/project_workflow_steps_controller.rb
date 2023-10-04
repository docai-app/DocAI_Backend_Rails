# frozen_string_literal: true

module Api
  module V1
    class ProjectWorkflowStepsController < ApiController
      before_action :authenticate_user!

      def index
        @project_workflow_steps = ProjectWorkflowStep.where(assignee_id: current_user.id)
        @project_workflow_steps = @project_workflow_steps.where(status: params[:status]) if params[:status].present?
        @project_workflow_steps = @project_workflow_steps.page params[:page]
        render json: { success: true, project_workflow_steps: @project_workflow_steps, meta: pagination_meta(@project_workflow_steps) },
               status: :ok
      end

      def show
        @project_workflow_step = ProjectWorkflowStep.find(params[:id])
        render json: { success: true, project_workflow_step: @project_workflow_step }, status: :ok
      end

      def show_by_project_workflow_id
        @project_workflow_steps = ProjectWorkflowStep.where(project_workflow_id: params[:project_workflow_id]).where(assignee_id: current_user.id)
        @project_workflow_steps = @project_workflow_steps.where(status: params[:status]) if params[:status].present?
        render json: { success: true, project_workflow_steps: @project_workflow_steps }, status: :ok
      end

      def create
        @project_workflow_step = ProjectWorkflowStep.new(project_workflow_step_params)
        @project_workflow_step.user_id = current_user.id if current_user.present?
        if @project_workflow_step.save
          render json: { success: true, project_workflow_step: @project_workflow_step }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @project_workflow_step = ProjectWorkflowStep.find(params[:id])
        if @project_workflow_step.update(project_workflow_step_params)
          render json: { success: true, project_workflow_step: @project_workflow_step }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @project_workflow_step = ProjectWorkflowStep.find(params[:id])
        if @project_workflow_step.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def project_workflow_step_params
        params.require(:project_workflow_step).permit(:name, :description, :assignee_id, :deadline, :status,
                                                      :project_workflow_id)
      end

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end
    end
  end
end

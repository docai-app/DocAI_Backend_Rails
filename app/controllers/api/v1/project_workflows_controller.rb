# frozen_string_literal: true

module Api
  module V1
    class ProjectWorkflowsController < ApiController
      def index
        @project_workflows = ProjectWorkflow.all.page params[:page]
        render json: { success: true, project_workflows: @project_workflows, meta: pagination_meta(@project_workflows) },
               status: :ok
      end

      def show
        @project_workflow = ProjectWorkflow.find(params[:id]).as_json(include: :steps)
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
      end

      def create
        @project_workflow = ProjectWorkflow.new(project_workflow_params)
        @project_workflow.user_id = current_user.id if current_user.present?
        steps = params[:steps]
        if @project_workflow.save
          steps.each do |step|
            @project_workflow.steps << ProjectWorkflowStep.create(
              name: step[:name],
              description: step[:description],
              user_id: @project_workflow.user_id,
              assignee_id: step[:assignee_id],
              deadline: step[:deadline],
              project_workflow_id: @project_workflow.id
            )
          end
          render json: { success: true, project_workflow: @project_workflow.as_json(include: :steps) }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @project_workflow = ProjectWorkflow.find(params[:id])
        if @project_workflow.update(project_workflow_params)
          render json: { success: true, project_workflow: @project_workflow }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @project_workflow = ProjectWorkflow.find(params[:id])
        if @project_workflow.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def project_workflow_params
        params.require(:project_workflow).permit(:name, :description, :deadline, :folder_id)
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

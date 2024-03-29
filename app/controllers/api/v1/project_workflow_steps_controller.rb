# frozen_string_literal: true

module Api
  module V1
    class ProjectWorkflowStepsController < ApiController
      # before_action :authenticate_user!

      def index
        # @project_workflow_steps = ProjectWorkflowStep.where('assignee_id = ? OR user_id = ?', current_user.id, current_user.id)
        @project_workflow_steps = ProjectWorkflowStep.where(assignee_id: current_user.id)
        @project_workflow_steps = @project_workflow_steps.where(status: params[:status]) if params[:status].present?
        @project_workflow_steps = @project_workflow_steps.includes(%i[project_workflow
                                                                      assignee]).as_json(include: %i[project_workflow
                                                                                                     assignee])
        @project_workflow_steps = Kaminari.paginate_array(@project_workflow_steps).page(params[:page])
        render json: { success: true, project_workflow_steps: @project_workflow_steps, meta: pagination_meta(@project_workflow_steps) },
               status: :ok
      end

      def show
        @project_workflow_step = ProjectWorkflowStep.find(params[:id]).includes(%i[project_workflow
                                                                                   assignee]).as_json(include: %i[
                                                                                                        project_workflow assignee
                                                                                                      ])
        render json: { success: true, project_workflow_step: @project_workflow_step }, status: :ok
      end

      def show_by_project_workflow_id
        @project_workflow_steps = ProjectWorkflowStep.where(project_workflow_id: params[:project_workflow_id])
        @project_workflow_steps = @project_workflow_steps.where(status: params[:status]) if params[:status].present?
        render json: { success: true, project_workflow_steps: @project_workflow_steps }, status: :ok
      end

      def create
        @project_workflow_step = ProjectWorkflowStep.create(project_workflow_step_params)
        @project_workflow_step.user_id = current_user.id if current_user.present?
        @project_workflow_step.assignee_id = current_user.id unless params[:assignee_id].present?
        @project_workflow_step.deadline = params[:deadline] if params[:deadline].present?
        @project_workflow_step.description = params[:description] if params[:description].present?
        @project_workflow_step.is_human = params[:is_human] if params[:is_human].present?

        if params[:project_workflow_id].present?
          @project_workflow = ProjectWorkflow.find(params[:project_workflow_id])
          @project_workflow.steps << @project_workflow_step
        end

        if @project_workflow_step.save
          render json: { success: true, project_workflow_step: @project_workflow_step }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, errors: e.message }, status: :unprocessable_entity
      end

      def update
        @wfs = ProjectWorkflowStep.find(params[:id])
        @wfs.name = params[:name] if params[:name].present?
        @wfs.description = params[:description] if params[:description].present?
        @wfs.criteria = params[:criteria] if params[:criteria].present?
        @wfs.status = params[:status] if params[:status].present?
        @wfs.deadline = params[:deadline] if params[:deadline].present?
        @wfs.dag_id = params[:dag_id] if params[:dag_id].present?
        @wfs.assignee_id = params[:assignee_id] if params[:assignee_id].present?
        @wfs.is_human = params[:is_human] if params[:is_human].present?
        @wfs.save
        render json: { success: true, project_workflow_step: @wfs }, status: :ok
      end

      def destroy
        @project_workflow_step = ProjectWorkflowStep.find(params[:id])
        if @project_workflow_step.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def start
        @wfs = ProjectWorkflowStep.find(params[:id])
        if @wfs.start
          render json: { success: true, project_workflow_step: @wfs }, status: :ok
        else
          render json: { success: false, errors: @wfs.errors.full_messages }, status: :unprocessable_entity
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

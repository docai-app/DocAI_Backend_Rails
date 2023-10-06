# frozen_string_literal: true

module Api
  module V1
    class ProjectWorkflowsController < ApiController
      def index
        @project_workflows = ProjectWorkflow.all.as_json(include: :steps)
        if params[:is_template].present?
          @project_workflows = @project_workflows.where(is_template: params[:is_template])
        end
        @project_workflows = Kaminari.paginate_array(@project_workflows).page(params[:page])
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

        if @project_workflow.save
          chatbot = create_chatbot(@project_workflow)
          create_workflow_steps(params[:steps])

          render json: { success: true, project_workflow: @project_workflow.as_json(include: :steps), chatbot: },
                 status: :ok
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
        params.require(:project_workflow).permit(:name, :description, :deadline, :folder_id, :is_template,
                                                 :is_process_workflow)
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

      def create_workflow_steps(steps)
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
      end

      def create_chatbot(project_workflow)
        Chatbot.create(
          name: project_workflow.name,
          user_id: project_workflow.user_id,
          object_type: 'ProjectWorkflow',
          object_id: project_workflow.id,
          source: { folder_id: [project_workflow.folder_id] }
        )
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class ProjectWorkflowsController < ApiController
      def index
        @project_workflows = ProjectWorkflow.where(user_id: current_user.id).includes([:steps])
        
        
        # 其實 is template 同 is process workflow 好似係一樣的野，唔知之前 api 用左邊個，就咁兩個都寫
        if params[:is_template].present?
          @project_workflows = @project_workflows.where(is_template: params[:is_template]) #.includes([:steps])
        end

        if params[:is_process_workflow].present?
          @project_workflows = @project_workflows.where(is_process_workflow: params[:is_process_workflow]) #.includes([:steps])
        end

        @project_workflows = @project_workflows.includes([:steps]).as_json(include: :steps)
        @project_workflows = Kaminari.paginate_array(@project_workflows).page(params[:page])
        render json: { success: true, project_workflows: @project_workflows, meta: pagination_meta(@project_workflows) },
               status: :ok
      end

      def show
        @project_workflow = ProjectWorkflow.find(params[:id]).as_json(include: { steps: { include: :assignee } })
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
      end

      def create
        @project_workflow = ProjectWorkflow.new(project_workflow_params)
        @project_workflow.user_id = current_user.id if current_user.present?
        @project_workflow.description = params[:description]
        @project_workflow.is_process_workflow = params[:is_process_workflow]

        if @project_workflow.save
          chatbot = create_chatbot(@project_workflow) if current_user.present?
          create_workflow_steps(params[:steps])

          render json: { success: true, project_workflow: @project_workflow.as_json(include: :steps), chatbot: },
                 status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @project_workflow = ProjectWorkflow.find(params[:id])
        @project_workflow.name = params[:name] if params[:name].present?
        @project_workflow.description = params[:description] if params[:description].present?
        @project_workflow.status = params[:status] if params[:status].present?
        if params[:is_process_workflow].present?
          @project_workflow.is_process_workflow = params[:is_process_workflow].to_b
        end

        if @project_workflow.save
          update_chatbot_folder_id if params[:folder_id].present?
          render json: { success: true, project_workflow: @project_workflow }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def duplicate
        @project_workflow = ProjectWorkflow.find(params[:id])
        new_wf = @project_workflow.duplicate!
        render json: { success: false, project_workflow: new_wf }, status: :ok
      end

      def start
        @project_workflow = ProjectWorkflow.find(params[:id])
        @project_workflow.start!
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
      end

      def pause
        @project_workflow = ProjectWorkflow.find(params[:id])
        @project_workflow.pause!
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
      end

      def resume
        @project_workflow = ProjectWorkflow.find(params[:id])
        @project_workflow.resume!
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
      end

      def restart
        @project_workflow = ProjectWorkflow.find(params[:id])
        @project_workflow.restart!
        render json: { success: true, project_workflow: @project_workflow }, status: :ok
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
            project_workflow_id: @project_workflow.id,
            dag_id: step[:dag_id]
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

      def update_chatbot_folder_id
        @chatbot = Chatbot.find_by(object_id: @project_workflow.id, object_type: 'ProjectWorkflow')
        @chatbot.source = { folder_id: [params[:folder_id]] }
        @chatbot.save
      end
    end
  end
end

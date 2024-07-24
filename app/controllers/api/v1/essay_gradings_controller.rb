# frozen_string_literal: true

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!

      def index
        # @essay_gradings = current_general_user.essay_gradings.select("id, topic, created_at, updated_at, status")
        @essay_gradings = current_general_user.essay_gradings.includes(:essay_assignment).joins(:essay_assignment).select('essay_gradings.id, essay_gradings.topic, essay_gradings.created_at, essay_gradings.updated_at, essay_gradings.status, essay_assignments.category as essay_assignment_category, essay_assignments.assignment AS assignment_name').order('updated_at desc')
        @essay_gradings = Kaminari.paginate_array(@essay_gradings).page(params[:page]).per(params[:count] || 10)
        render json: {
          success: true,
          essay_gradings: @essay_gradings.map do |eg|
            {
              id: eg.id,
              topic: eg.topic,
              created_at: eg.created_at,
              updated_at: eg.updated_at,
              status: eg.status,
              assignment_name: eg.assignment_name,
              category: eg.essay_assignment&.category
            }
          end,
          meta: pagination_meta(@essay_gradings)
        }, status: :ok
        # render json: { success: true, essay_gradings: @essay_gradings, meta: pagination_meta(@essay_gradings) }, status: :ok
      end

      # 顯示特定的 EssayGrading
      def show
        set_essay_grading
        render json: { success: true, essay_grading: @essay_grading }
      end

      def create
        set_essay_assignment_by_code

        puts "set_essay_assignment_by_code: #{@essay_assignment.inspect}"

        @essay_grading = @essay_assignment.essay_gradings.new(essay_grading_params)
        @essay_grading.general_user = current_general_user
        @essay_grading.topic = @essay_assignment.topic
        @essay_grading.app_key = @essay_assignment.app_key

        if @essay_grading.save
          render json: { success: true, essay_grading: @essay_grading }, status: :created
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # def create
      #   @essay_grading = EssayGrading.new(essay_grading_params)
      #   @essay_grading.general_user = current_general_user
      #   @essay_grading['grading'] = {}
      #   @essay_grading['grading']['app_key'] = params[:app_key]
      #   if @essay_grading.save
      #     # 創建後調用服務
      #     EssayGradingService.new(current_general_user.id, @essay_grading).run_workflow
      #     render json: @essay_grading, status: :created
      #   else
      #     render json: { errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
      #   end
      # end

      def update
        @user = current_general_user
        if @user.update(user_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      # 設置特定的 EssayGrading
      def set_essay_grading
        # @essay_grading = current_general_user.essay_gradings.find(params[:id])
        @essay_grading = EssayGrading.find(params[:id])
      end

      def set_essay_assignment_by_code
        @essay_assignment = EssayAssignment.find_by!(code: params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def essay_grading_params
        params.require(:essay_grading).permit(
          :essay, 
          :topic, 
          grading: [
            :app_key, 
            comprehension: [
              questions: [
                :question, 
                :answer, 
                :user_answer, 
                { options: {} }
              ]
            ]
          ]
        )
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

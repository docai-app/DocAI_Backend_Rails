# frozen_string_literal: true

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!

      def index
        # 联合查询，以便选择 essay_assignment 中的 newsfeed_id 字段
        @essay_gradings = current_general_user.essay_gradings
                                              .joins(:essay_assignment)
                                              .select(
                                                'essay_gradings.id, 
                                                 essay_gradings.topic, 
                                                 essay_gradings.created_at, 
                                                 essay_gradings.updated_at, 
                                                 essay_gradings.status, 
                                                 essay_assignments.category as essay_assignment_category, 
                                                 essay_assignments.assignment AS assignment_name, 
                                                 essay_assignments.meta ->> \'newsfeed_id\' AS newsfeed_id'
                                              )
                                              .order('updated_at desc')
      
        @essay_gradings = Kaminari.paginate_array(@essay_gradings).page(params[:page]).per(params[:count] || 10)
        
        # 获取 category 的字符串表示
        categories = EssayAssignment.categories.invert
      
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
              category: categories[eg['essay_assignment_category']],  # 使用 categories 映射获取字符串表示
              newsfeed_id: eg.newsfeed_id  # 添加 newsfeed_id
            }
          end,
          meta: pagination_meta(@essay_gradings)
        }, status: :ok
        # render json: { success: true, essay_gradings: @essay_gradings, meta: pagination_meta(@essay_gradings) }, status: :ok
      end

      # 顯示特定的 EssayGrading
      def show
        set_essay_grading
        # 预加载 essay_assignment 关联
        # @essay_grading = @essay_grading.includes(:essay_assignment).find(params[:id])
      
        # 获取 category 的字符串表示
        categories = EssayAssignment.categories.invert
      
        render json: { 
          success: true, 
          essay_grading: {
            id: @essay_grading.id,
            topic: @essay_grading.topic,
            created_at: @essay_grading.created_at,
            updated_at: @essay_grading.updated_at,
            status: @essay_grading.status,
            number_of_suggestion: @essay_grading.grading['number_of_suggestion'],
            questions_count: @essay_grading.grading.dig('comprehension', 'questions_count'),
            full_score: @essay_grading.grading.dig('comprehension', 'full_score'),
            score: @essay_grading.grading.dig('comprehension', 'score'),
            grading: @essay_grading.grading,
            essay: @essay_grading.essay,
            general_user: {
              id: @essay_grading.general_user.id,
              nickname: @essay_grading.general_user.nickname,
              class_name: @essay_grading.general_user.banbie,
              class_no: @essay_grading.general_user.class_no
            },
            essay_assignment: {
              id: @essay_grading.essay_assignment.id,
              app_key: @essay_grading.essay_assignment.app_key,
              name: @essay_grading.essay_assignment.name,
              category: @essay_grading.essay_assignment.category,
              newsfeed_id: @essay_grading.essay_assignment.newsfeed_id,
              created_at: @essay_grading.essay_assignment.created_at,
              updated_at: @essay_grading.essay_assignment.updated_at
            }
          }
        }, status: :ok
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

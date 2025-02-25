# frozen_string_literal: true

module Api
  module V1
    class EssayAssignmentsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment, only: %i[update destroy]

      before_action :set_essay_assignment_by_code, only: %i[show_only]
      before_action :aienglish_access, only: %i[show_only]

      def index
        @essay_assignments = current_general_user.essay_assignments
        @essay_assignments = @essay_assignments.where(category: params[:category]) if params[:category].present?
        @essay_assignments = @essay_assignments.select(:id, :number_of_submission, :rubric, :title, :hints, :category, :answer_visible,
                                                       :topic, :created_at, :updated_at, :code, :assignment).order('created_at desc')

        @essay_assignments = Kaminari.paginate_array(@essay_assignments).page(params[:page])
        render json: { success: true, essay_assignments: @essay_assignments, meta: pagination_meta(@essay_assignments) },
               status: :ok
      end

      def show_only
        render json: { success: true, essay_assignment: @essay_assignment }
      end

      def read
        @essay_assignment = EssayAssignment.find(params[:id])
        render json: { success: true, essay_assignment: @essay_assignment }
      end

      def show
        @essay_assignment = EssayAssignment.find(params[:id])

        @essay_gradings = @essay_assignment.essay_gradings
                                           .joins(:general_user)
                                           .joins(:essay_assignment)
                                           .select(
                                             'essay_gradings.id,
                                      essay_gradings.general_user_id,
                                      essay_assignments.category as essay_assignment_category,
                                      essay_gradings.meta ->> \'newsfeed_id\' AS newsfeed_id,
                                      essay_gradings.using_time,
                                      essay_gradings.created_at,
                                      essay_gradings.updated_at,
                                      essay_gradings.status,
                                      essay_gradings.grading,
                                      COALESCE(essay_gradings.grading ->> \'number_of_suggestion\', \'null\') AS number_of_suggestion,
                                      general_users.nickname,
                                      general_users.banbie,
                                      general_users.class_no,
                                      COALESCE(essay_gradings.grading -> \'comprehension\' ->> \'questions_count\', \'null\') AS questions_count,
                                      COALESCE(essay_gradings.grading -> \'comprehension\' ->> \'full_score\', \'null\') AS full_score,
                                      COALESCE(essay_gradings.grading -> \'comprehension\' ->> \'score\', \'null\') AS score'
                                           )
                                           .includes(:general_user).order('created_at asc')

        render json: {
          success: true,
          essay_assignment: @essay_assignment,
          essay_gradings: @essay_gradings.sort_by { |eg| eg.class_no.to_i }.map do |eg|
            # 解析 grading JSON
            grading_json = JSON.parse(eg["grading"]["data"]["text"]) rescue {}

            # 提取每個 criterion 的分數和總分
            scores = grading_json.each_with_object({}) do |(key, value), result|
              if key.start_with?('Criterion') && value.is_a?(Hash)
                value.each do |criterion_key, criterion_value|
                  # 排除不需要的键
                  unless ['Full Score', 'explanation'].include?(criterion_key)
                    result[criterion_key] = criterion_value
                  end
                end
              end
            end

            # 提取 Overall Score
            overall_score = grading_json["Overall Score"]
            the_full_score = grading_json["Full Score"]

            {
              id: eg.id,
              general_user: {
                id: eg.general_user_id,
                nickname: eg.nickname,
                class_name: eg.banbie,
                class_no: eg.class_no
              },
              using_time: eg['using_time'],
              newsfeed_id: eg['newsfeed_id'],
              category: eg['essay_assignment_category'],
              created_at: eg.created_at,
              updated_at: eg.updated_at,
              status: eg.status,
              number_of_suggestion: eg['number_of_suggestion'] == 'null' ? nil : eg['number_of_suggestion'],
              questions_count: eg['questions_count'] == 'null' ? nil : eg['questions_count'],
              full_score: eg['full_score'] == 'null' ? nil : eg['full_score'],
              score: eg['score'] == 'null' ? nil : eg['score'],
              scores: scores,
              overall_score: overall_score,
              the_full_score: the_full_score
            }
          end
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def create
        @essay_assignment = EssayAssignment.new(essay_assignment_params)
        @essay_assignment.general_user_id = current_general_user.id
        if @essay_assignment.save
          render json: { success: true, essay_assignment: @essay_assignment }, status: :created
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @essay_assignment.update(essay_assignment_params)
          render json: { success: true, essay_assignment: @essay_assignment }, status: :ok
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @essay_assignment.destroy
        render json: { success: true, message: 'EssayAssignment deleted successfully' }, status: :ok
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :ok
      end

      def set_essay_assignment_by_code
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :ok
      end

      def aienglish_access
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])

        # 檢查 meta 欄位中的 aienglish_features_list
        if current_general_user.aienglish_features_list.include?(@essay_assignment.category)
          true
        else
          render json: { success: false, error: 'Access denied' }, status: :ok
        end
      end

      def essay_assignment_params
        params.require(:essay_assignment).permit(
          :topic,
          :assignment,
          :title,
          :remark,
          :hints,
          :category,
          :answer_visible,
          rubric: [
            :name,
            { app_key: %i[grading general_context] } # 允许嵌套的 app_key
          ],
          meta: [:newsfeed_id, self_upload_newsfeed: {}]
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
